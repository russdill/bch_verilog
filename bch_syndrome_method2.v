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
	output [M-1:0] synN
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
	localparam signed EARLY = BITS - SYNDROME_SIZE;

	reg [M-1:0] lfsr = 0;
	wire [BITS-1:0] shifted_in;
	wire [SYNDROME_SIZE-1:0] in_enc_early;
	wire [SYNDROME_SIZE-1:0] in_enc;
	wire [SYNDROME_SIZE-1:0] lfsr_enc;

	function [BITS-1:0] reverse;
		input [BITS-1:0] in;
		integer i;
	begin
		for (i = 0; i < BITS; i = i + 1)
			reverse[i] = in[BITS - i - 1];
	end
	endfunction

	/*
	 * Shift input so that pad the start with 0's, and finish on the final
	 * bit.
	 */
	generate
		if (REM) begin
			reg [RUNT-1:0] runt = 0;
			assign shifted_in = reverse((data_in << RUNT) | (start ? 0 : runt));
			always @(posedge clk)
				runt <= #TCQ data_in >> REM;
		end else
			assign shifted_in = reverse(data_in);
	endgenerate

	/*
	 * If the input size fills the LFSR reg, we need to calculate those
	 * additional lfsr terms.
	 */
	if (EARLY > 0) begin : INPUT_LFSR
		lfsr_term #(SYNDROME_SIZE, SYNDROME_POLY, EARLY) u_in_terms(
			.in(shifted_in[BITS-1:SYNDROME_SIZE]),
			.out(in_enc_early)
		);
	end else
		assign in_enc_early = 0;

	/* This can be pipelined */
	assign in_enc = in_enc_early ^ shifted_in;

	/* Calculate the next lfsr state (without input) */
	wire [BITS-1:0] lfsr_input;
	assign lfsr_input = EARLY > 0 ? (lfsr << EARLY) : (lfsr >> -EARLY);
	lfsr_term #(SYNDROME_SIZE, SYNDROME_POLY, BITS) u_lfsr_term (
		.in(lfsr_input),
		.out(lfsr_enc)
	);

	/* Calculate remainder */
	always @(posedge clk)
		if (start)
			lfsr <= #TCQ in_enc;
		else if (ce)
			lfsr <= #TCQ (lfsr << BITS) ^ lfsr_enc ^ in_enc;

	assign synN = lfsr;
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
