`timescale 1ns / 1ps

`include "bch_defs.vh"

/*
 * Tradition chien search, for each cycle, check if the
 * sum of all the equations is zero, if so, this location
 * is a bit error.
 */
module bch_error_tmec #(
	parameter [`BCH_PARAM_SZ-1:0] P = `BCH_SANE,
	parameter BITS = 1,
	parameter REG_RATIO = 1,
	parameter PIPELINE_STAGES = 0
) (
	input clk,
	input start,			/* Latch inputs, start calculating */
	input [`BCH_SIGMA_SZ(P)-1:0] sigma,
	output ready,
	output first,			/* First valid output data */
	output last,
	output valid,			/* Outputting data */
	output [BITS-1:0] err
);
	`include "bch.vh"

	localparam TCQ = 1;
	localparam M = `BCH_M(P);
	localparam RUNT = `BCH_DATA_BITS(P) % BITS;

	wire [BITS*`BCH_SIGMA_SZ(P)-1:0] chien;
	wire [BITS*M-1:0] eq;
	wire [BITS*M-1:0] eq_pipelined;
	wire [BITS-1:0] err_raw;
	wire first_raw;
	wire last_raw;
	wire valid_raw;
	genvar i;

	if (`BCH_T(P) == 1)
		tmec_does_not_support_sec u_tdnss();

	if (PIPELINE_STAGES > 2)
		tmec_only_supports_2_pipeline_stages u_tos2ps();

	bch_chien #(P, BITS, REG_RATIO) u_chien(
		.clk(clk),
		.start(start),
		.ready(ready),
		.sigma(sigma),
		.chien(chien),
		.first(first_raw),
		.last(last_raw),
		.valid(valid_raw)
	);

	pipeline #(PIPELINE_STAGES) u_out_pipeline [3] (
		.clk(clk),
		.i({first_raw, last_raw, valid_raw}),
		.o({first, last, valid})
	);

	finite_parallel_adder #(M, `BCH_T(P)+1) u_adder [BITS-1:0] (chien, eq);
	pipeline #(PIPELINE_STAGES > 1) u_eq_pipeline [BITS*M] (clk, eq, eq_pipelined);

	for (i = 0; i < BITS; i = i + 1) begin : BIT
		assign err_raw[i] = !eq_pipelined[i*M+:M] && (!RUNT || i < RUNT || !last);
	end
	pipeline #(PIPELINE_STAGES > 0) u_err_pipeline [BITS] (clk, err_raw, err);
endmodule
