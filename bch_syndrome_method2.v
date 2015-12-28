/*
 * BCH Encode/Decoder Modules
 *
 * Copyright 2014 - Russ Dill <russ.dill@asu.edu>
 * Distributed under 2-clause BSD license as contained in COPYING file.
 */
`timescale 1ns / 1ps

`include "bch_defs.vh"

/*
 * Calculate syndrome method 2:
 *
 * (0) r(x) = a_j * f_j(x) + b_j(x)
 * (1) S_j = b_j(alpha^j)
 * (2) b_j(x) = r(x) % f_j(x)
 * 
 * First divide r(x) by f_j(x) to obtain the remainder, b_j(x). Then calculate
 * b_j(alpha^j).
 *
 * Pipelining can only help when BITS > DEGREE
 */
module dsynN_method2 #(
	parameter [`BCH_PARAM_SZ-1:0] P = `BCH_SANE,
	parameter SYN = 0,
	parameter DEGREE = `BCH_M(P),
	parameter BITS = 1,
	parameter PIPELINE_STAGES = 0
) (
	input clk,
	input ce,				/* Accept additional bit */
	input start,				/* Accept first bit of syndrome */
	input start_pipelined,			/* Start delayed by one if there are
						 * two pipeline stages */
	input [BITS-1:0] data_in,	
	input [BITS-1:0] data_pipelined,	/* One stage delay (if necessary) */
	output [`BCH_M(P)-1:0] synN
);
	`include "bch.vh"

	localparam M = `BCH_M(P);

	function [M-1:0] syndrome_poly;
		input dummy;
		integer i;
		integer j;
		integer a;
		integer first;
		integer done;
		integer curr;
		integer prev;
		reg [M*M-1:0] poly;
	begin

		poly = 1;
		first = lpow(M, SYN);
		a = first;
		done = 0;
		while (!done) begin
			prev = 0;
			for (j = 0; j < M; j = j + 1) begin
				curr = poly[j*M+:M];
				poly[j*M+:M] = finite_mult(M, curr, a) ^ prev;
				prev = curr;
			end

			a = finite_mult(M, a, a);
			if (a == first)
				done = 1;
		end

		syndrome_poly = 0;
		for (i = 0; i < M; i = i + 1)
			syndrome_poly[i] = poly[i*M+:M] ? 1 : 0;
	end
	endfunction

	localparam TCQ = 1;
	localparam SYNDROME_POLY = syndrome_poly(0);
	localparam signed EARLY = BITS - DEGREE;

	if (PIPELINE_STAGES > 2)
		dsynN_method2_only_supports_2_pipeline_stage u_dm2os2ps();

	reg [DEGREE-1:0] lfsr = 0;
	wire [DEGREE-1:0] in_enc_early;
	wire [DEGREE-1:0] in_enc_early_pipelined;
	wire [DEGREE-1:0] in_enc;
	wire [DEGREE-1:0] in_enc_pipelined;
	wire [DEGREE-1:0] lfsr_enc;

	/*
	 * If the input size fills the LFSR reg, we need to calculate those
	 * additional lfsr terms.
	 */
	if (EARLY > 0) begin : INPUT_LFSR
		lfsr_term #(DEGREE, SYNDROME_POLY, EARLY) u_in_terms(
			.in(data_in[BITS-1:DEGREE]),
			.out(in_enc_early)
		);
	end else
		assign in_enc_early = 0;

	pipeline_ce #(PIPELINE_STAGES > 0) u_in_pipeline [DEGREE-1:0] (
		.clk(clk),
		.ce(ce),
		.i(in_enc_early),
		.o(in_enc_early_pipelined)
	);

	assign in_enc = in_enc_early_pipelined ^ data_pipelined;
	pipeline_ce #(PIPELINE_STAGES > 1) u_enc_pipeline [DEGREE-1:0] (
		.clk(clk),
		.ce(ce),
		.i(in_enc),
		.o(in_enc_pipelined)
	);

	/* Calculate the next lfsr state (without input) */
	wire [BITS-1:0] lfsr_input;
	assign lfsr_input = EARLY > 0 ? (lfsr << EARLY) : (lfsr >> -EARLY);
	lfsr_term #(DEGREE, SYNDROME_POLY, BITS) u_lfsr_term (
		.in(lfsr_input),
		.out(lfsr_enc)
	);

	/* Calculate remainder */
	always @(posedge clk)
		if (ce) begin
			if (start_pipelined)
				/* Use start as set/reset if possible */
				lfsr <= #TCQ PIPELINE_STAGES ? 0 : in_enc_pipelined;
			else
				lfsr <= #TCQ (lfsr << BITS) ^ lfsr_enc ^ in_enc_pipelined;
		end

	assign synN = lfsr;
endmodule

module syndrome_expand_method2 #(
	parameter [`BCH_PARAM_SZ-1:0] P = `BCH_SANE,
	parameter DAT = 0
) (
	input [`BCH_M(P)-1:0] in,
	output [`BCH_M(P)-1:0] out
);
	localparam M = `BCH_M(P);

	/* Perform b_j(alpha^j) */
	parallel_standard_power #(M, DAT) u_power(
		.standard_in(in),
		.standard_out(out)
	);
endmodule
