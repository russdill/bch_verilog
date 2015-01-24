/*
 * BCH Encode/Decoder Modules
 *
 * Copright 2014 - Russ Dill <russ.dill@asu.edu>
 * Distributed under 2-clause BSD license as contained in COPYING file.
 */
`timescale 1ns / 1ps

`include "bch_defs.vh"
`include "config.vh"

/* Chien search, determines roots of a polynomial defined over a finite field */
module bch_chien_reg #(
	parameter [`BCH_PARAM_SZ-1:0] P = `BCH_SANE,
	parameter REG = 1,
	parameter SKIP = 0,
	parameter STRIDE = 1
) (
	input clk,
	input start,
	input [M-1:0] in,
	output reg [M-1:0] out = 0
);
	`include "bch.vh"

	localparam TCQ = 1;
	localparam M = `BCH_M(P);

	wire [M-1:0] mul_out;
	wire [M-1:0] mul_out_start;

	if (!SKIP)
		assign mul_out_start = in;
	else begin
		/* Initialize with coefficients of the error location polynomial */
		if (`CONFIG_CONST_OP)
			parallel_standard_multiplier_const2 #(M, lpow(M, REG * SKIP)) u_mult_start(
				.standard_in(in),
				.standard_out(mul_out_start)
			);
		else
			parallel_standard_multiplier #(M) u_mult_start(
				.standard_in1(in),
				.standard_in2(lpow(M, REG * SKIP)),
				.standard_out(mul_out_start)
			);
	end

	/* Multiply by alpha^P */
	if (`CONFIG_CONST_OP)
		parallel_standard_multiplier_const1 #(M, lpow(M, REG * STRIDE)) u_mult(
			.standard_in(out),
			.standard_out(mul_out)
		);
	else
		parallel_standard_multiplier #(M) u_mult(
			.standard_in1(lpow(M, REG * STRIDE)),
			.standard_in2(out),
			.standard_out(mul_out)
		);
	always @(posedge clk)
		out <= #TCQ start ? mul_out_start : mul_out;
endmodule

module bch_chien_expand #(
	parameter [`BCH_PARAM_SZ-1:0] P = `BCH_SANE,
	parameter REG = 1,
	parameter SKIP = 1
) (
	input [M-1:0] in,
	output [M-1:0] out
);
	`include "bch.vh"

	localparam TCQ = 1;
	localparam M = `BCH_M(P);

	parallel_standard_multiplier_const1 #(M, lpow(M, REG * SKIP)) u_mult(
		.standard_in(in),
		.standard_out(out)
	);
endmodule

/*
 * Each register is loaded with the associated syndrome
 * and multiplied by alpha^i each cycle.
 */
module bch_chien #(
	parameter [`BCH_PARAM_SZ-1:0] P = `BCH_SANE,
	parameter BITS = 1,

	/*
	 * For multi-bit output, Only implement every Nth register. Use async
	 * logic to fill in the remaining values.
	 */
	parameter REG_RATIO = BITS > 8 ? 8 : BITS
) (
	input clk,
	input start,
	input [`BCH_SIGMA_SZ(P)-1:0] sigma,
	output reg ready = 1,
	output reg first = 0,		/* First valid output data */
	output reg last = 0,		/* Last valid output cycle */
	output reg valid = 0,		/* Outputting data */
	output [`BCH_SIGMA_SZ(P)*BITS-1:0] chien
);
	`include "bch.vh"

	localparam TCQ = 1;
	localparam M = `BCH_M(P);
	localparam T = `BCH_T(P);
	localparam CYCLES = (`BCH_DATA_BITS(P) + BITS - 1) / BITS;
	localparam DONE = lfsr_count(M, CYCLES - 2);
	localparam SKIP = `BCH_K(P) - `BCH_DATA_BITS(P);

	if (REG_RATIO > BITS)
		chien_reg_ratio_must_be_less_than_or_equal_to_bits u_crrmbltoeqb();

	reg first_cycle = 0;
	wire penult;

	if (CYCLES == 1)
		assign penult = first_cycle;
	else if (CYCLES == 2)
		assign penult = first;
	else begin
		wire [M-1:0] count;
		lfsr_counter #(M) u_counter(
			.clk(clk),
			.reset(first_cycle),
			.ce(valid),
			.count(count)
		);
		assign penult = count == DONE;
	end

	always @(posedge clk) begin
		first_cycle <= #TCQ start;
		first <= #TCQ first_cycle;
		valid <= #TCQ !ready;
		last <= #TCQ penult;

		if (start)
			ready <= #TCQ 0;
		else if (penult)
			ready <= #TCQ 1;
	end

	genvar i, b;
	generate
	for (b = 0; b < BITS; b = b + 1) begin : BIT
		for (i = 0; i <= T; i = i + 1) begin : REG
			if (!(b % REG_RATIO)) begin : ORIG
				bch_chien_reg #(M, i + 1, SKIP + b - BITS + 1 + `BCH_N(P), BITS) u_chien_reg(
					.clk(clk),
					.start(start),
					.in(sigma[i*M+:M]),
					.out(chien[((BITS-b-1)*(T+1)+i)*M+:M])
				);
			end else begin : EXPAND
				bch_chien_expand #(M, i + 1, b % REG_RATIO) u_chien_expand(
					.in(chien[((BITS-b+(b%REG_RATIO)-1)*(T+1)+i)*M+:M]),
					.out(chien[((BITS-b-1)*(T+1)+i)*M+:M])
				);
			end
		end
	end
	endgenerate
endmodule
