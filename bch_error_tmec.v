/*
 * BCH Encode/Decoder Modules
 *
 * Copyright 2014 - Russ Dill <russ.dill@asu.edu>
 * Distributed under 2-clause BSD license as contained in COPYING file.
 */
`timescale 1ns / 1ps

`include "config.vh"
`include "bch_defs.vh"

/*
 * Tradition chien search, for each cycle, check if the
 * value of all the sumuations is zero, if so, this location
 * is a bit error.
 */
module bch_error_tmec #(
	parameter [`BCH_PARAM_SZ-1:0] P = `BCH_SANE,
	parameter BITS = 1,
	parameter REG_RATIO = BITS > 8 ? 8 : BITS,
	parameter PIPELINE_STAGES = 0,
	parameter ACCUM = PIPELINE_STAGES > 1 ? `CONFIG_LUT_SZ : 1
) (
	input clk,
	input start,			/* Latch inputs, start calculating */
	input [`BCH_SIGMA_SZ(P)-1:0] sigma,
	output first,			/* First valid output data */
	output [BITS-1:0] err
);
	`include "bch.vh"

	localparam TCQ = 1;
	localparam M = `BCH_M(P);

	/*
	 * We have to sum all the chien outputs. Split up the outputs and sum
	 * them into accumulators. For instance, if REGS == 13, and ACCUM == 3
	 * then we group together the chien outputs into 5 regs, 4 regs, and
	 * 4 regs. We then sum together those accumulators.
	 */
	localparam REGS = `BCH_T(P) + 1;
	localparam W_A = (REGS + ACCUM - 1) / ACCUM;
	localparam W_B = REGS / ACCUM;
	localparam ACCUM_A = REGS - W_B * ACCUM;
	localparam ACCUM_B = ACCUM - ACCUM_A;

	wire [BITS*`BCH_CHIEN_SZ(P)-1:0] chien;
	wire [ACCUM*BITS*M-1:0] accum;
	wire [ACCUM*BITS*M-1:0] accum_pipelined;
	wire [BITS*M-1:0] sum;
	wire [BITS*M-1:0] sum_pipelined;
	wire [BITS-1:0] err_raw;
	wire first_raw;
	genvar i, j;

	if (`BCH_T(P) == 1)
		tmec_does_not_support_sec u_tdnss();

	if (PIPELINE_STAGES > 3)
		tmec_only_supports_3_pipeline_stages u_tos2ps();

	if (ACCUM > REGS)
		tmec_accum_must_be_less_than_or_equal_to_regs u_tambltoretr();

	if (ACCUM > 1 && PIPELINE_STAGES < 2)
		tmec_accum_requires_2_or_more_pipeline_stages u_tar2omps();

	bch_chien #(P, BITS, REG_RATIO) u_chien(
		.clk(clk),
		.start(start),
		.sigma(sigma),
		.chien(chien),
		.first(first_raw)
	);

	pipeline #(PIPELINE_STAGES) u_out_pipeline (
		.clk(clk),
		.i(first_raw),
		.o(first)
	);

	for (i = 0; i < BITS; i = i + 1) begin : BITS_BLOCK
		for (j = 0; j < ACCUM_A; j = j + 1) begin : ACCUM_A_BLOCK
			finite_parallel_adder #(M, W_A) u_adder(
				.in(chien[i*`BCH_CHIEN_SZ(P)+j*W_A*M+:W_A*M]),
				.out(accum[(i*ACCUM+j)*M+:M])
			);
		end
		for (j = 0; j < ACCUM_B; j = j + 1) begin : ACCUM_B_BLOCK
			finite_parallel_adder #(M, W_B) u_adder(
				.in(chien[i*`BCH_CHIEN_SZ(P)+(ACCUM_A*W_A+j*W_B)*M+:W_B*M]),
				.out(accum[(i*ACCUM+ACCUM_A+j)*M+:M])
			);
		end
	end

	pipeline #(PIPELINE_STAGES > 1) u_accum_pipeline [ACCUM*BITS*M-1:0] (clk, accum, accum_pipelined);

	finite_parallel_adder #(M, ACCUM) u_adder [BITS-1:0] (accum_pipelined, sum);

	pipeline #(PIPELINE_STAGES > 2) u_sum_pipeline [BITS*M-1:0] (clk, sum, sum_pipelined);

	zero_cla #(M, PIPELINE_STAGES > 2 ? 1 : ACCUM) u_zero [BITS-1:0] (sum_pipelined, err_raw);

	pipeline #(PIPELINE_STAGES > 0) u_err_pipeline1 [BITS-1:0] (
		.clk(clk),
		.i(err_raw[BITS-1:0]),
		.o(err[BITS-1:0])
	);

endmodule
