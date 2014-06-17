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
	parameter BITS = 1,
	parameter REG_RATIO = 1
) (
	input clk,
	input start,			/* Accept first bit of syndrome */
	input ce,
	input [BITS-1:0] data_in,
	output reg [M-1:0] synN = 0
);
	`include "bch_syndrome.vh"

	localparam TCQ = 1;
	localparam M = `BCH_M(P);
	localparam signed SKIP = `BCH_K(P) - `BCH_DATA_BITS(P);
	localparam SYN = idx2syn(M, IDX);
	/* Our current syndrome processing is reversed */
	localparam LPOW_S_BITS = lpow(SB, m2n(SB) - (SYN * BITS) % m2n(SB));
	localparam SYNDROME_SIZE = syndrome_size(M, SYN);
	localparam SB = SYNDROME_SIZE;
	localparam REGS = (BITS + REG_RATIO - 1) / REG_RATIO;

	/*
	 * Reduce pow reg size by only having a reg for every other,
	 * or every 4th, etc register, filling in the others with async logic
	 */
	reg [REGS*SB-1:0] pow = 0;
	wire [REGS*SB-1:0] pow_next;
	wire [REGS*SB-1:0] pow_initial;
	wire [REGS*SB-1:0] pow_curr;
	wire [BITS*SB-1:0] pow_all;
	wire [BITS*SB-1:0] terms;
	wire [SB-1:0] syn_next;
	genvar i;

	/* Probably needs a load cycle */
	for (i = 0; i < BITS; i = i + 1) begin : GEN_TERMS
		if (!(i % REG_RATIO)) begin
			localparam LPOW = lpow(SB, m2n(SB) - (SYN * (i + SKIP + 1)) % m2n(SB));
			assign pow_initial[(i/REG_RATIO)*SB+:SB] = LPOW;
			assign pow_curr[(i/REG_RATIO)*SB+:SB] = start ?
						pow_initial[(i/REG_RATIO)*SB+:SB] : pow[(i/REG_RATIO)*SB+:SB];
			assign pow_all[i*SB+:SB] = pow_curr[(i/REG_RATIO)*SB+:SB];
		end else begin
			localparam [SB-1:0] LPOW = lpow(SB, m2n(SB) - (SYN * (i % REG_RATIO)) % m2n(SB));
			parallel_standard_multiplier #(SB) u_mult(
				.standard_in1(LPOW),
				.standard_in2(pow_curr[(i/REG_RATIO)*SB+:SB]),
				.standard_out(pow_all[i*SB+:SB])
			);
		end
		assign terms[i*SB+:SB] = {SB{data_in[i]}} & pow_all[i*SB+:SB];
	end

	parallel_standard_multiplier #(SB, REGS) u_mult(
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
		if (ce) begin
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
