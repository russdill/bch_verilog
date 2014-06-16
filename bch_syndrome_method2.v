`timescale 1ns / 1ps

/*
 * Calculate syndrome method 2:
 *
 * (0) r(x) = a_j * f_j(x) + b_j(x)
 * (1) S_j = b_j(alpha^j)
 * (2) b_j(x) = r(x) % f_j(x)
 * 
 * First divide r(x) by f_j(x) to obtain the remainder, b_j(x). Then calculate
 * b_j(alpha^j).
 */
module dsynN_method2 #(
	parameter [`BCH_PARAM_SZ-1:0] P = `BCH_SANE,
	parameter IDX = 0,
	parameter BITS = 1
) (
	input clk,
	input ce,			/* Accept additional bit */
	input start,			/* Accept first bit of syndrome */
	input [BITS-1:0] data_in,
	output reg [M-1:0] synN = 0
);
	`include "bch_syndrome.vh"

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
	localparam SYN = idx2syn(M, IDX);
	localparam SYNDROME_POLY = syndrome_poly(0);
	localparam SYNDROME_SIZE = syndrome_size(M, SYN);
	localparam REM = `BCH_CODE_BITS(P) % BITS;
	localparam RUNT = BITS - REM;

	wire [BITS-1:0] shifted_in;

	wire [SYNDROME_SIZE-1:0] synN_enc;
	lfsr_term #(SYNDROME_SIZE, SYNDROME_POLY, BITS) u_lfsr_term (
		.in(synN[SYNDROME_SIZE-1:SYNDROME_SIZE-BITS]),
		.out(synN_enc)
	);

	function [BITS-1:0] reverse;
		input [BITS-1:0] in;
		integer i;
	begin
		for (i = 0; i < BITS; i = i + 1)
			reverse[i] = in[BITS - i - 1];
	end
	endfunction

	generate
		if (REM) begin
			reg [RUNT-1:0] runt = 0;
			assign shifted_in = {data_in[REM-1:0], (start ? {RUNT{1'b0}} : runt)};
			always @(posedge clk)
				runt <= #TCQ data_in[BITS-1:REM];
		end else
			assign shifted_in = data_in;
	endgenerate

	/* Calculate remainder */
	always @(posedge clk) begin
		if (start)
			synN <= #TCQ {reverse(shifted_in)};
		else if (ce)
			synN <= #TCQ {synN[SYNDROME_SIZE-BITS-1:0], {BITS{1'b0}}} ^ synN_enc ^ reverse(shifted_in);
	end
endmodule

module syndrome_expand_method2 #(
	parameter [`BCH_PARAM_SZ-1:0] P = `BCH_SANE,
	parameter DAT = 0
) (
	input [M-1:0] in,
	output [M-1:0] out
);
	localparam M = `BCH_M(P);

	/* Perform b_j(alpha^j) */
	parallel_standard_power #(M, DAT) u_power(
		.standard_in(in),
		.standard_out(out)
	);
endmodule
