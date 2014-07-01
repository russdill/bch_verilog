/*
 * BCH Encode/Decoder Modules
 *
 * Copright 2014 - Russ Dill <russ.dill@asu.edu>
 * Distributed under 2-clause BSD license as contained in COPYING file.
 */
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
	parameter REG_RATIO = BITS > 8 ? 8 : BITS,
	parameter PIPELINE_STAGES = 0
) (
	input clk,
	input start,				/* Accept first bit of syndrome */
	input start_pipelined,			/* Start delayed by one if there are
						 * two pipeline stages */
	input ce,
	input [BITS-1:0] data_pipelined,	/* One stage delay (if necessary) */
	output reg [M-1:0] synN = 0
);
	`include "bch_syndrome.vh"

	localparam TCQ = 1;
	localparam M = `BCH_M(P);
	localparam signed SKIP = `BCH_K(P) - `BCH_DATA_BITS(P);
	localparam SYN = idx2syn(M, IDX);
	/* Our current syndrome processing is reversed */
	localparam LPOW_S_BITS = lpow(SB, `BCH_M2N(SB) - (SYN * BITS) % `BCH_M2N(SB));
	localparam SYNDROME_SIZE = syndrome_size(M, SYN);
	localparam SB = SYNDROME_SIZE;
	localparam REGS = (BITS + REG_RATIO - 1) / REG_RATIO;

	if (PIPELINE_STAGES > 2)
		dsynN_method1_only_supports_2_pipeline_stage u_dm1os2ps();

	if (REG_RATIO > BITS)
		syndrome_reg_ratio_must_be_less_than_or_equal_to_bits u_srrmbltoeqb();

	function [REGS*SB-1:0] pow_initial;
		input dummy;
		integer i;
	begin
		for (i = 0; i < REGS; i = i + 1)
			pow_initial[i*SB+:SB] = lpow(SB, `BCH_M2N(SB) - ((SYN * (i * REG_RATIO + SKIP + 1)) % `BCH_M2N(SB)));
	end
	endfunction

	localparam [REGS*SB-1:0] POW_INITIAL = pow_initial(0);

	/*
	 * Reduce pow reg size by only having a reg for every other,
	 * or every 4th, etc register, filling in the others with async logic
	 */
	reg [REGS*SB-1:0] pow = POW_INITIAL;
	wire [REGS*SB-1:0] pow_next;
	wire [REGS*SB-1:0] pow_curr;
	wire [BITS*SB-1:0] pow_all;
	wire [BITS*SB-1:0] terms;
	wire [SB-1:0] terms_summed;
	wire [SB-1:0] terms_summed_pipelined;
	genvar i;

	/* Not enough pipeline stages for set/reset, must use mux */
	assign pow_curr = (PIPELINE_STAGES < 2 && start) ? POW_INITIAL : pow;

	for (i = 0; i < BITS; i = i + 1) begin : GEN_TERMS
		wire [SB-1:0] curr = pow_curr[(i/REG_RATIO)*SB+:SB];
		if (!(i % REG_RATIO))
			assign pow_all[i*SB+:SB] = curr;
		else begin
			localparam [SB-1:0] LPOW = lpow(SB, `BCH_M2N(SB) - ((SYN * (i % REG_RATIO)) % `BCH_M2N(SB)));
			parallel_standard_multiplier_const1 #(SB, LPOW) u_mult(
				.standard_in(curr),
				.standard_out(pow_all[i*SB+:SB])
			);
		end
		assign terms[i*SB+:SB] = data_pipelined[i] ? pow_all[i*SB+:SB] : 0;
	end

	parallel_standard_multiplier_const1 #(SB, LPOW_S_BITS[SB-1:0]) u_mult [REGS-1:0] (
		.standard_in(pow_curr),
		.standard_out(pow_next)
	);

	finite_parallel_adder #(SB, BITS) u_adder(
		.in(terms),
		.out(terms_summed)
	);

	pipeline_ce #(PIPELINE_STAGES > 0) u_summed_pipeline [SB-1:0] (
		.clk(clk),
		.ce(ce),
		.i(terms_summed),
		.o(terms_summed_pipelined)
	);

	always @(posedge clk) begin
		if (ce) begin
			/* Utilize set/reset signal if possible */
			pow <= #TCQ (PIPELINE_STAGES > 1 && start) ? POW_INITIAL : pow_next;
			if (start_pipelined)
				synN <= #TCQ PIPELINE_STAGES ? 0 : terms_summed_pipelined;
			else
				synN <= #TCQ synN ^ terms_summed_pipelined;
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
