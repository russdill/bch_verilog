`timescale 1ns / 1ps

/*
 * Calculate syndrome method 2:
 *
 * (0) r(x) = a_j * f_j(x) + b_j(x)
 * (1) S_j = b_j(alpha^j)
 * (2) b_j(x) = r(x) % f_j(x)
 * 
 * First divide r(x) by f_j(x) to obtain the remained, b_j(x). Then calculate
 * b_j(alpha^j).
 */
module dsynN_method2 #(
	parameter M = 4,
	parameter T = 3,
	parameter IDX = 0
) (
	input clk,
	input ce,			/* Accept additional bit */
	input start,			/* Accept first bit of syndrome */
	input data_in,
	output reg [M-1:0] synN = 0
);
	`include "bch_syndrome.vh"

	function [MAX_M-1:0] syndrome_poly;
		input [31:0] m;
		input [31:0] s;
		integer i;
		integer j;
		integer n;
		integer a;
		integer first;
		integer done;
		integer curr;
		integer prev;
		reg [MAX_M*MAX_M-1:0] poly;
	begin
		n = m2n(m);

		poly = 1;
		first = lpow(m, s);
		a = first;
		done = 0;
		while (!done) begin
			prev = 0;
			for (j = 0; j < m; j = j + 1) begin
				curr = poly[j*MAX_M+:MAX_M];
				poly[j*MAX_M+:MAX_M] = finite_mult(m, curr, a) ^ prev;
				prev = curr;
			end

			a = finite_mult(m, a, a);
			if (a == first)
				done = 1;
		end

		for (i = 0; i < m; i = i + 1)
			syndrome_poly[i] = poly[i*MAX_M+:MAX_M] ? 1 : 0;
	end
	endfunction

	localparam TCQ = 1;
	localparam SYN = idx2syn(M, IDX);
	localparam SYNDROME_POLY = syndrome_poly(M, SYN);
	localparam SYNDROME_SIZE = syndrome_size(M, SYN);

	genvar bit_pos;

	/* Calculate remainder */
	always @(posedge clk) begin
		if (start)
			synN <= #TCQ {{M-1{1'b0}}, data_in};
		else if (ce)
			synN <= #TCQ {synN[M-2:0], data_in} ^ (SYNDROME_POLY & {M{synN[SYNDROME_SIZE-1]}});
	end
endmodule

module syndrome_expand_method2 #(
	parameter M = 4,
	parameter DAT = 0
) (
	input [M-1:0] in,
	output [M-1:0] out
);
	/* Perform b_j(alpha^j) */
	parallel_standard_power #(M, DAT) u_power(
		.standard_in(in),
		.standard_out(out)
	);
endmodule
