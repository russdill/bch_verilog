`timescale 1ns / 1ps

module sim #(
	parameter N = 15,
	parameter K = 5,
	parameter T = 3,
	parameter OPTION = "SERIAL"
) (
	input clk,
	input reset,
	input [K-1:0] din,
	input [N-1:0] error,
	output vdin,
	output vdout,
	output reg wrongNow = 0,
	output reg wrong = 0,
	output [K-1:0] dout
);

`include "bch.vh"

localparam TCQ = 1;
localparam M = n2m(N);
localparam INTERLEAVE = calc_interleave(N, T);
localparam ITERATION = M + 2;
localparam CHPE = T * ITERATION - 2;
localparam VDOUT = CHPE + INTERLEAVE + 2 - CHPE % INTERLEAVE;
localparam BUF_SIZE = (INTERLEAVE > 1) ? (N + 2 + VDOUT / INTERLEAVE) : (N + VDOUT + 1);

reg [K-1:0] encB = 0;
reg [K-1:0] decB = 0;
reg [N-1:0] errB = 0;
reg [BUF_SIZE-1:0] comB = 0;
reg [(INTERLEAVE > 1 ? $clog2(INTERLEAVE+1) : 1)-1:0] ci = 0;
reg vdinPrev = 0;
reg resetDec = 0;

wire encBOut;
wire err;
wire comBOut;
wire encIn;
wire vdin0_1;
wire decIn;
wire wrongIn;
wire clkEnc;
wire clkEncEn;
wire encOut;
wire decOut;

bch_encode #(N, K, T, OPTION) u_bch_encode(
	.clk(clkEnc),
	.reset(reset),
	.din(encIn),
	.vdin(vdin),
	.dout(encOut)
);

bch_decode #(N, K, T) u_bch_decode(
	.clk(clk),
	.reset(resetDec),
	.din(decIn),
	.vdout(vdout),
	.dout(decOut)
);

assign encBOut = encB[0];
assign err = errB[0];
assign comBOut = comB[BUF_SIZE-1];
assign encIn = encBOut && !reset;
assign vdin0_1 = (!vdinPrev && vdin) || reset;
assign decIn = (encOut ^ err) && !reset;
assign wrongIn = (decOut !== comBOut) && !reset && vdout && (vdout !== 1'bx) && (vdout !== 1'bz);
assign clkEnc = INTERLEAVE > 1 ? (clkEncEn && !clk) : clk;
assign clkEncEn = INTERLEAVE > 1 ? !ci : 1'b1;
assign dout = decB;

always @(posedge clk) begin
	if (vdout)
		decB <= #TCQ {decOut, decB[K-1:1]};
	ci <= #TCQ (reset || ci == INTERLEAVE - 1) ? 0 : ci + 1'b1;
	if (reset)
		wrong <= #TCQ 1'b0;
	else if (wrongIn)
		wrong <= #TCQ 1'b1;
	wrongNow <= #TCQ wrongIn;
	resetDec <= #TCQ reset;
end

always @(posedge clkEnc) begin
	encB <= #TCQ !vdin ? din : {1'b0, encB[K-1:1]};
	errB <= #TCQ vdin0_1 ? error : {1'b0, errB[N-1:1]};
	comB <= #TCQ {comB[BUF_SIZE-2:0], encIn};
	vdinPrev <= #TCQ vdin;
end

endmodule
