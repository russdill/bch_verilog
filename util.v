/*
 * BCH Encode/Decoder Modules
 *
 * Copright 2014 - Russ Dill <russ.dill@asu.edu>
 * Distributed under 2-clause BSD license as contained in COPYING file.
 */
`timescale 1ns / 1ps

module counter #(
	parameter MAX = 15
) (
	input clk,
	input reset,
	input ce,
	output reg [log2(MAX)-1:0] count = 0
);
	`include "bch.vh"

	localparam TCQ = 1;

	always @(posedge clk)
		if (reset)
			count <= #TCQ 1'b0;
		else if (ce)
			count <= #TCQ count + 1'b1;
endmodule

module pipeline_ce_reset #(
	parameter STAGES = 0
) (
	input clk,
	input ce,
	input reset,
	input i,
	output o
);
	localparam TCQ = 1;
	if (!STAGES)
		assign o = i;
	else begin
		reg [STAGES-1:0] pipeline = 0;
		assign o = pipeline[STAGES-1];
		always @(posedge clk)
			if (reset)
				pipeline <= #TCQ pipeline << 1;
			else if (ce)
				pipeline <= #TCQ (pipeline << 1) | i;
	end
endmodule

module pipeline_ce #(
	parameter STAGES = 0
) (
	input clk,
	input ce,
	input i,
	output o
);
	pipeline_ce_reset #(STAGES) u_ce(clk, ce, 1'b0, i, o);
endmodule

module pipeline_reset #(
	parameter STAGES = 0
) (
	input clk,
	input reset,
	input i,
	output o
);
	pipeline_ce_reset #(STAGES) u_ce(clk, 1'b1, reset, i, o);
endmodule

module pipeline #(
	parameter STAGES = 0
) (
	input clk,
	input i,
	output o
);
	pipeline_ce_reset #(STAGES) u_ce(clk, 1'b1, 1'b0, i, o);
endmodule

module reverse_words #(
	parameter M = 4,
	parameter WORDS = 1
) (
	input [M*WORDS-1:0] in,
	output [M*WORDS-1:0] out
);
	genvar i;
	for (i = 0; i < WORDS; i = i + 1) begin : REV
		assign out[i*M+:M] = in[(WORDS-i-1)*M+:M];
	end
endmodule

module rotate_right #(
	parameter M = 4,
	parameter S = 0
) (
	input [M-1:0] in,
	output [M-1:0] out
);
	wire [M*2-1:0] in2 = {in, in};
	assign out = in2[S%M+:M];
endmodule

module rotate_left #(
	parameter M = 4,
	parameter S = 0
) (
	input [M-1:0] in,
	output [M-1:0] out
);
	wire [M*2-1:0] in2 = {in, in};
	assign out = in2[M-(S%M)+:M];
endmodule
