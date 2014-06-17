`timescale 1ns / 1ps

`include "bch_defs.vh"


/* Chien search, determines roots of a polynomial defined over a finite field */
module bch_chien_reg #(
	parameter [`BCH_PARAM_SZ-1:0] P = `BCH_SANE,
	parameter REG = 1,
	parameter SKIP = 0
) (
	input clk,
	input err,		/* Error was found so correct it */
	input ce,
	input start,
	input [M-1:0] in,
	output reg [M-1:0] out = 0
);
	`include "bch.vh"

	localparam TCQ = 1;
	localparam M = `BCH_M(P);
	localparam LPOW_REG = lpow(M, REG);
	/* preperform the proper number of multiplications */
	localparam LPOW_SKIP = lpow(M, REG * SKIP);

	wire [M-1:0] mul_out;

	/* Multiply by alpha^P */
	parallel_standard_multiplier #(M) u_mult(
		.standard_in1(start ? LPOW_SKIP[M-1:0] : LPOW_REG[M-1:0]),
		/* Initialize with coefficients of the error location polynomial */
		.standard_in2(start ? in : (out ^ err)),
		.standard_out(mul_out)
	);

	always @(posedge clk)
		if (start || ce)
			out <= #TCQ mul_out;
endmodule

/*
 * Each register is loaded with the associated syndrome
 * and multiplied by alpha^i each cycle.
 */
module bch_chien #(
	parameter [`BCH_PARAM_SZ-1:0] P = `BCH_SANE
) (
	input clk,
	input start,
	input accepted,
	input [`BCH_SIGMA_SZ(P)-1:0] sigma,
	input err_feedback,
	output reg busy = 0,
	output reg first = 0,		/* First valid output data */
	output reg last = 0,		/* Last valid output cycle */
	output reg valid = 0,		/* Outputting data */
	output [`BCH_SIGMA_SZ(P)-1:0] chien
);
	`include "bch.vh"

	localparam TCQ = 1;
	localparam M = `BCH_M(P);
	localparam T = `BCH_T(P);
	localparam DONE = lfsr_count(M, `BCH_DATA_BITS(P) - 2);

	wire [M-1:0] count;
	reg first_cycle = 0;
	
	lfsr_counter #(M) u_counter(
		.clk(clk),
		.reset(first_cycle),
		.ce(valid && accepted),
		.count(count)
	);

	always @(posedge clk) begin
		first_cycle <= #TCQ start && !busy;
		first <= #TCQ first_cycle;
		valid <= #TCQ busy;
		last <= #TCQ count == DONE;
		if (start && !busy)
			busy <= #TCQ 1;
		else if (count == DONE)
			busy <= #TCQ 0;
	end

	genvar i;
	generate
	for (i = 0; i <= T; i = i + 1) begin : DCH
		bch_chien_reg #(M, i + 1, `BCH_K(P) - `BCH_DATA_BITS(P)) u_ch(
			.clk(clk),
			.err(err_feedback),
			.ce(valid || first_cycle),
			.start(start),
			.in(sigma[i*M+:M]),
			.out(chien[i*M+:M])
		);
	end
	endgenerate
endmodule
