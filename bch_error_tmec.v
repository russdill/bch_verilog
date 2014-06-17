`timescale 1ns / 1ps

`include "bch_defs.vh"

/*
 * Tradition chien search, for each cycle, check if the
 * sum of all the equations is zero, if so, this location
 * is a bit error.
 */
module bch_error_tmec #(
	parameter [`BCH_PARAM_SZ-1:0] P = `BCH_SANE
) (
	input clk,
	input start,			/* Latch inputs, start calculating */
	input [`BCH_SIGMA_SZ(P)-1:0] sigma,
	input accepted,
	output busy,
	output first,			/* First valid output data */
	output last,
	output valid,			/* Outputting data */
	output err
);
	`include "bch.vh"

	localparam TCQ = 1;
	localparam M = `BCH_M(P);

	wire [`BCH_SIGMA_SZ(P)-1:0] chien;
	wire [M-1:0] eq;

	if (`BCH_T(P) == 1)
		tmec_does_not_support_sec u_tdnss();

	bch_chien #(P) u_chien(
		.clk(clk),
		.sigma(sigma),
		.err_feedback(1'b0),
		.start(start),
		.chien(chien),
		.accepted(accepted),
		.busy(busy),
		.first(first),
		.last(last),
		.valid(valid)
	);

	/* Candidate for pipelining */
	finite_parallel_adder #(M, `BCH_T(P)+1) u_dcheq(chien, eq);
	assign err = valid && !eq;
endmodule
