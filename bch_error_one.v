/*
 * BCH Encode/Decoder Modules
 *
 * Copyright 2015 - Russ Dill <russ.dill@asu.edu>
 * Distributed under 2-clause BSD license as contained in COPYING file.
 */
`timescale 1ns / 1ps

`include "config.vh"
`include "bch_defs.vh"

/* Reduced chien search for cases with only 1 bit error */
module bch_error_one #(
	parameter [`BCH_PARAM_SZ-1:0] P = `BCH_SANE,
	parameter BITS = 1,
	parameter PIPELINE_STAGES = 0
) (
	input clk,
	input start,			/* Latch inputs, start calculating */
	input [`BCH_M(P)*2-1:0] sigma,
	output first,			/* First valid output data */
	output [BITS-1:0] err
);
	`include "bch.vh"

	localparam TCQ = 1;
	localparam M = `BCH_M(P);
	localparam SKIP = `BCH_DATA_BITS(P) - `BCH_K(P) + `BCH_N(P);

	wire [BITS-1:0] err_raw;
	wire [M-1:0] chien;

	if (`BCH_T(P) == 1)
		one_does_not_support_sec u_odnss();

	bch_chien_reg #(M, 1, 0, BITS) u_chien_reg(
		.clk(clk),
		.start(start),
		.in(sigma[M+:M]),
		.out(chien)
	);

	genvar b;
	generate
	for (b = 0; b < BITS; b = b + 1) begin : BIT
		assign err_raw[b] = chien == lpow(M, SKIP + b);
	end
	endgenerate

	pipeline #(2 + PIPELINE_STAGES) u_first_pipeline (
		.clk(clk),
		.i(start),
		.o(first)
	);

	pipeline #(PIPELINE_STAGES) u_out_pipeline [BITS-1:0] (
		.clk(clk),
		.i(err_raw),
		.o(err)
	);
endmodule
