/*
 * BCH Encode/Decoder Modules
 *
 * Copyright 2014 - Russ Dill <russ.dill@asu.edu>
 * Distributed under 2-clause BSD license as contained in COPYING file.
 */
`timescale 1ns / 1ps

module counter #(
	parameter MAX = 15,
	parameter START = 0,
	parameter signed INC = 1
) (
	input clk,
	input reset,
	input ce,
	output reg [$clog2(MAX+1)-1:0] count = START
);
	localparam TCQ = 1;

	always @(posedge clk)
		if (reset)
			count <= #TCQ START;
		else if (ce)
			count <= #TCQ count + INC;
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

module mux_one #(
	parameter WIDTH = 2,
	parameter WIDTH_SZ = $clog2(WIDTH+1)
) (
	input [WIDTH-1:0] in,
	input [WIDTH_SZ-1:0] sel,
	output out
);
	assign out = in[sel];
endmodule

module mux_shuffle #(
	parameter U = 2,
	parameter V = 2
) (
	input [U*V-1:0] in,
	output [V*U-1:0] out
);
	genvar u, v;
	generate
	for (u = 0; u < U; u = u + 1) begin : _U
		for (v = 0; v < V; v = v + 1) begin : _V
			assign out[v*U+u] = in[u*V+v];
		end
	end
	endgenerate
endmodule

module mux #(
	parameter WIDTH = 2,
	parameter BITS = 1,
	parameter WIDTH_SZ = $clog2(WIDTH+1)
) (
	input [BITS*WIDTH-1:0] in,
	input [WIDTH_SZ-1:0] sel,
	output [BITS-1:0] out
);
	wire [WIDTH*BITS-1:0] shuffled;
	mux_shuffle #(WIDTH, BITS) u_mux_shuffle(in, shuffled);
	mux_one #(WIDTH) u_mux_one [BITS-1:0] (shuffled, sel, out);
endmodule
