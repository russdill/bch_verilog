/*
 * BCH Encode/Decoder Modules
 *
 * Copyright 2014 - Russ Dill <russ.dill@asu.edu>
 * Distributed under 2-clause BSD license as contained in COPYING file.
 */
`timescale 1ns / 1ps

`include "bch_defs.vh"

/* Make the ECC on erased flash be all 1's */
module bch_blank_ecc #(
	parameter [`BCH_PARAM_SZ-1:0] P = `BCH_SANE,
	parameter BITS = 1,
	parameter PIPELINE_STAGES = 0
) (
	input clk,
	input start,				/* First cycle */
	input ce,				/* Accept input word/cycle output word */
	output [BITS-1:0] xor_out,
	output first,				/* First output cycle */
	output last				/* Last output cycle */
);
	`include "bch.vh"
	`include "bch_encode.vh"

	localparam TCQ = 1;
	localparam M = `BCH_M(P);
	localparam EB = `BCH_ECC_BITS(P);
	localparam ECC_WORDS = (EB + BITS - 1) / BITS;
	localparam [EB-1:0] ENC = encoder_poly(0);

	if (PIPELINE_STAGES > 1)
		blank_ecc_only_supports_1_pipeline_stage u_beos1ps();

	function [ECC_WORDS*BITS-1:0] erased_ecc;
		input dummy;
		reg [EB-1:0] lfsr;
	begin
		lfsr = 0;
		repeat (`BCH_DATA_BITS(P))
			lfsr = (lfsr << 1) ^ (lfsr[EB-1] ? 0 : ENC);
		erased_ecc = ~(lfsr << (ECC_WORDS*BITS - EB));
	end
	endfunction

	localparam [ECC_WORDS*BITS-1:0] ERASED_ECC = erased_ecc(0);

	wire _last;

	if (ECC_WORDS == 1) begin
		assign _last = start;
		assign xor_out = ERASED_ECC;
	end else if (ECC_WORDS == 2) begin
		reg start0 = 0;

		always @(posedge clk) begin
			if (start)
				start0 <= #TCQ start;
			else if (ce)
				start0 <= #TCQ 0;
		end

		assign _last = start0;

		if (PIPELINE_STAGES > 0) begin
			assign xor_out = start0 ? ERASED_ECC[BITS+:BITS] :
				ERASED_ECC[0+:BITS];
		end else
			assign xor_out = start ? ERASED_ECC[BITS+:BITS] :
				ERASED_ECC[0+:BITS];
	end else begin
		reg [(ECC_WORDS-1)*BITS-1:0] ecc_xor = ERASED_ECC;
		wire [$clog2(ECC_WORDS+1)-1:0] count;

		assign _last = count == 0;

		counter #(ECC_WORDS, ECC_WORDS - 2, -1) u_counter(
			.clk(clk),
			.reset(start),
			.ce(ce),
			.count(count)
		);

		if (PIPELINE_STAGES > 0) begin
			/* Add registered outputs to distributed RAM */
			reg [BITS-1:0] xor_bits = ERASED_ECC[(ECC_WORDS-1)*BITS+:BITS];
			always @(posedge clk) begin
				if (start)
					xor_bits <= #TCQ ERASED_ECC[(ECC_WORDS-1)*BITS+:BITS];
				else if (ce)
					xor_bits <= #TCQ ecc_xor[count*BITS+:BITS];
			end
			assign xor_out = xor_bits;
		end else
			assign xor_out = start ?
				ERASED_ECC[(ECC_WORDS-1)*BITS+:BITS] :
				ecc_xor[count*BITS+:BITS];

	end

	pipeline_ce #(PIPELINE_STAGES > 0) u_control_pipeline [1:0] (
		.clk(clk),
		.ce(ce || start),
		.i({start, _last}),
		.o({first, last})
	);
endmodule
