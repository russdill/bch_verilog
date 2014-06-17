`timescale 1ns / 1ps

`include "bch_defs.vh"


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
	localparam LPOW_REG = lpow(M, REG * STRIDE);
	/* preperform the proper number of multiplications */
	localparam LPOW_SKIP = lpow(M, REG * SKIP);

	wire [M-1:0] mul_out;

	/* Multiply by alpha^P */
	parallel_standard_multiplier #(M) u_mult(
		.standard_in1(start ? LPOW_SKIP[M-1:0] : LPOW_REG[M-1:0]),
		/* Initialize with coefficients of the error location polynomial */
		.standard_in2(start ? in : out),
		.standard_out(mul_out)
	);

	always @(posedge clk)
		out <= #TCQ mul_out;
endmodule

/*
 * Each register is loaded with the associated syndrome
 * and multiplied by alpha^i each cycle.
 */
module bch_chien #(
	parameter [`BCH_PARAM_SZ-1:0] P = `BCH_SANE,
	parameter BITS = 1
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
	/* FIXME: Support async register expansion */
	for (i = 0; i <= T; i = i + 1) begin : REG
		for (b = 0; b < BITS; b = b + 1) begin : BITS
			bch_chien_reg #(M, i + 1, SKIP + b - BITS + 1 + `BCH_N(P), BITS) u_chien_reg(
				.clk(clk),
				.start(start),
				.in(sigma[i*M+:M]),
				.out(chien[(i*BITS+b)*M+:M])
			);
		end
	end
	endgenerate
endmodule
