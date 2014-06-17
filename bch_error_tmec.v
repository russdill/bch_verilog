`timescale 1ns / 1ps

`include "bch_defs.vh"

/*
 * Tradition chien search, for each cycle, check if the
 * sum of all the equations is zero, if so, this location
 * is a bit error.
 */
module bch_error_tmec #(
	parameter [`BCH_PARAM_SZ-1:0] P = `BCH_SANE,
	parameter BITS = 1
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

	wire [BITS*`BCH_SIGMA_SZ(P)-1:0] chien;
	wire [BITS*M-1:0] eq;
	genvar i;

	if (`BCH_T(P) == 1)
		tmec_does_not_support_sec u_tdnss();

	bch_chien #(P, BITS) u_chien(
		.clk(clk),
		.start(start),
		.ready(ready),
		.sigma(sigma),
		.chien(chien),
		.first(first),
		.last(last),
		.valid(valid)
	);

	/* Candidate for pipelining */
	finite_parallel_adder #(M, `BCH_T(P)+1) u_adder [BITS-1:0] (chien, eq);
	for (i = 0; i < BITS; i = i + 1)
		assign err[i] = !eq[i*M+:M];
endmodule
