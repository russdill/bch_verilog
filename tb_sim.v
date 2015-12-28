/*
 * BCH Encode/Decoder Modules
 *
 * Copyright 2014 - Russ Dill <russ.dill@asu.edu>
 * Distributed under 2-clause BSD license as contained in COPYING file.
 */
`timescale 1ns / 1ps

module tb_sim;

`include "bch_params.vh"

parameter T = 3;
parameter OPTION = "SERIAL";
parameter DATA_BITS = 5;
parameter BITS = 1;
parameter REG_RATIO = 1;
parameter SEED = 0;

localparam BCH_PARAMS = bch_params(DATA_BITS, T);

reg [31:0] seed = SEED;

initial begin
	$dumpfile("test.vcd");
	$dumpvars(0);
end

localparam TCQ = 1;

reg clk = 0;
reg reset = 0;
reg [DATA_BITS-1:0] din = 0;
reg [$clog2(T+2)-1:0] nerr = 0;
reg [`BCH_CODE_BITS(BCH_PARAMS)-1:0] error = 0;

function [DATA_BITS-1:0] randk;
	input [31:0] useless;
	integer i;
begin
	for (i = 0; i < (31 + DATA_BITS) / 32; i = i + 1)
		if (i * 32 > DATA_BITS) begin
			if (DATA_BITS % 32)
				/* Placate isim */
				randk[i*32+:(DATA_BITS%32) ? (DATA_BITS%32) : 1] = $random(seed);
		end else
			randk[i*32+:32] = $random(seed);
end
endfunction

function integer n_errors;
	input [31:0] useless;
	integer i;
begin
	n_errors = (32'h7fff_ffff & $random(seed)) % (T + 1);
end
endfunction

function [`BCH_CODE_BITS(BCH_PARAMS)-1:0] rande;
	input [31:0] nerr;
	integer i;
begin
	rande = 0;
	while (nerr) begin
		i = (32'h7fff_ffff & $random(seed)) % (`BCH_CODE_BITS(BCH_PARAMS));
		if (!((1 << i) & rande)) begin
			rande = rande | (1 << i);
			nerr = nerr - 1;
		end
	end
end
endfunction

reg encode_start = 0;
wire wrong;
wire ready;
reg active = 0;

sim #(BCH_PARAMS, OPTION, BITS, REG_RATIO) u_sim(
	.clk(clk),
	.reset(1'b0),
	.data_in(din),
	.error(error),
	.ready(ready),
	.encode_start(active),
	.wrong(wrong)
);

always
	#5 clk = ~clk;

always @(posedge wrong)
	#10 $finish;

reg [31:0] s;

always @(posedge clk) begin
	if (ready) begin
		s = seed;
		#1;
		din <= randk(0);
		#1;
		nerr <= n_errors(0);
		#1;
		error <= rande(nerr);
		#1;
		active <= 1;
		$display("%b %d flips - %b (seed = %d)", din, nerr, error, s);
	end
end

initial begin
	$display("GF(2^%1d) (%1d, %1d/%1d, %1d) %s",
		`BCH_M(BCH_PARAMS), `BCH_N(BCH_PARAMS), `BCH_K(BCH_PARAMS),
		DATA_BITS, `BCH_T(BCH_PARAMS), OPTION);
	@(posedge clk);
	@(posedge clk);
	reset <= #1 1;
	@(posedge clk);
	@(posedge clk);
	reset <= #1 0;
end

endmodule
