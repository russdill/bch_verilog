`timescale 1ns / 1ps

/*
 * Calculate syndrome method 1:
 *
 * S_j = r_0 + alpha^j * (r_1 + alpha^j * ...(r_(n-2) + alpha^j * r_(n-1))...)
 *
 * 0: z = n - 1, accumulator = 0
 * 1: accumulator += r_z
 * 2: accumulator *= alpha^j
 * 3: z = z - 1
 * 4: z >= 0 -> goto 1
 *
 * takes n cycles
 */
module dsynN_method1 #(
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

	localparam TCQ = 1;
	localparam M = `BCH_M(P);
	localparam SKIP = `BCH_K(P) - `BCH_DATA_BITS(P);
	localparam SYN = idx2syn(M, IDX);
	/* Our current syndrome processing is reversed */
	localparam LPOW_S_BITS = lpow(SB, m2n(SB) - (SYN * BITS) % m2n(SB));
	localparam SYNDROME_SIZE = syndrome_size(M, SYN);
	localparam SB = SYNDROME_SIZE;

	reg [BITS*SB-1:0] pow = 0;
	wire [BITS*SB-1:0] pow_next;
	wire [BITS*SB-1:0] pow_curr;
	wire [BITS*SB-1:0] pow_initial;
	wire [BITS*SB-1:0] terms;
	wire [SB-1:0] syn_next;
	genvar i;

	/* Probably needs a load cycle */
	assign pow_curr = start ? pow_initial : pow;

	for (i = 0; i < BITS; i = i + 1) begin
		assign pow_initial[i*SB+:SB] = lpow(SB, m2n(SB) - (SYN * (i + SKIP + 1)) % m2n(SB));
		assign terms[i*SB+:SB] = {SB{data_in[i]}} & pow_curr[i*SB+:SB];
	end

	parallel_standard_multiplier #(SB, BITS) u_mult(
		.standard_in1(LPOW_S_BITS[SB-1:0]),
		.standard_in2(pow_curr),
		.standard_out(pow_next)
	);

	/* This can be pipelined */
	finite_parallel_adder #(SB, BITS + 1) u_adder(
		.in({start ? {SB{1'b0}} : synN, terms}),
		.out(syn_next)
	);

	always @(posedge clk) begin
		if (start || ce) begin
			pow <= #TCQ pow_next;
			synN <= #TCQ syn_next;
		end
	end
endmodule

module syndrome_expand_method1 #(
	parameter [`BCH_PARAM_SZ-1:0] P = `BCH_SANE
) (
	input [M-1:0] in,
	output [M-1:0] out
);
	localparam M = `BCH_M(P);
	assign out = in;
endmodule
