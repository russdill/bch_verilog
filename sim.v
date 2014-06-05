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
	output clkEnc,
	input encode_start,
	output encoded_penult,
	output vdout,
	output reg wrongNow = 0,
	output reg wrong = 0,
	output [K-1:0] dout
);

`include "bch.vh"

localparam TCQ = 1;
localparam M = n2m(N);
localparam INTERLEAVE = calc_interleave(N, T, OPTION == "SERIAL");
localparam ITERATION = calc_iteration(N, T, OPTION == "SERIAL");
if (OPTION != "SERIAL" && OPTION != "PARALLEL")
	illegal_option_value u_iov();
localparam CHPE = T * ITERATION - 2;
localparam VDOUT = (T < 3) ? 3 : (CHPE + INTERLEAVE + 2 - CHPE % INTERLEAVE);
localparam BUF_SIZE = (INTERLEAVE > 1) ? (N + 2 + VDOUT / INTERLEAVE) : (N + VDOUT + 1);

reg [K-1:0] encB = 0;
reg [K-1:0] decB = 0;
reg [N-1:0] errB = 0;
reg [BUF_SIZE-1:0] comB = 0;
reg [(INTERLEAVE > 1 ? $clog2(INTERLEAVE+1) : 1)-1:0] ci = 0;
reg resetDec = 0;

wire err;
wire decIn;
wire wrongIn;
wire clkEncEn;
wire encOut;
wire decOut;
wire encoded_first;
wire encoded_last;

initial
	$display("INTERLEAVE = %0d, ITERATION = %0d, CHPE = %0d, VDOUT = %0d, BUF_SIZE = %0d",
		INTERLEAVE, ITERATION, CHPE, VDOUT, BUF_SIZE);

bch_encode #(N, K, T, OPTION) u_bch_encode(
	.clk(clkEnc),
	.start(encode_start),
	.data_in(encode_start ? din[0] : encB[1]),
	.data_out(encOut),
	.first(encoded_first),
	.last(encoded_last),
	.penult(encoded_penult)
);

bch_decode #(N, K, T, OPTION) u_bch_decode(
	.clk(clk),
	.reset(resetDec),
	.start(encoded_first),
	.din(decIn),
	.vdout(vdout),
	.dout(decOut)
);

assign err = errB[0];
assign decIn = (encOut ^ err) && !reset;
assign wrongIn = ((decOut !== comB[0]) && !reset && vdout) || ((vdout === 1'bx) || (vdout === 1'bz));
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
	encB <= #TCQ encode_start ? din : {1'b0, encB[K-1:1]};
	errB <= #TCQ encode_start ? error : {1'b0, errB[N-1:1]};
	comB <= #TCQ {encode_start ? din[0] : encB[1], comB[BUF_SIZE-1:1]};
end

endmodule
