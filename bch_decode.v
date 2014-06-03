`timescale 1ns / 1ps

module bch_decode #(
	parameter N = 15,
	parameter K = 5,
	parameter T = 3,	/* Correctable errors */
	parameter OPTION = "SERIAL"
) (
	input clk,
	input reset,
	input din,
	output vdout,
	output reg dout = 0
);

`include "bch.vh"

localparam TCQ = 1;
localparam M = n2m(N);
localparam INTERLEAVE = calc_interleave(N, T);
localparam ITERATION = M + 2;
localparam CHPE = T * ITERATION - 2;
localparam _BUF_SIZE = CHPE / INTERLEAVE + 2;
localparam BUF_SIZE = (_BUF_SIZE > K + 1) ? K : _BUF_SIZE; /* FIXME: possible off by one?, comment indicates BUF_SIZE > K */
/* buf_size= chpe/interleave + 2 if buf_size<k+1; else buf_size= k */

reg [K-1:0] bufk = 0;
reg [BUF_SIZE-1:0] buf_ = 0;
wire [M*(2*T-1)-1:0] snNout;
wire [2*T*M-1:M] synN;
wire [M*(T+1)-1:0] cNout;

wire bsel;
wire synpe;
wire msmpe;
wire chpe;
wire drnzero;
wire snce;
wire cei;
wire bufCe;
wire bufkCe;
wire vdout1;
wire err;
wire c0first;
wire cce;
wire caLast;
wire cbBeg;
wire dringPe;

genvar i;

if (OPTION == "PARALLEL") begin
	bch_decode_parallel #(M, T) u_decode_parallel (
		.clk(clk),
		.synpe(synpe),
		.snce(snce),
		.bsel(bsel),
		.msmpe(msmpe),
		.chpe(chpe),
		.syn1(synN[1*M+:M]),
		.snNout(snNout),
		.drnzero(drnzero),
		.cNout(cNout)
	);
end else if (OPTION == "SERIAL") begin
	bch_decode_serial #(M, T) u_decode_serial (
		.clk(clk),
		.synpe(synpe),
		.snce(snce),
		.bsel(bsel),
		.caLast(caLast),
		.cbBeg(cbBeg),
		.msmpe(msmpe),
		.cce(cce),
		.dringPe(dringPe),
		.c0first(c0first),
		.syn1(synN[1*M+:M]),
		.snNout(snNout),
		.drnzero(drnzero),
		.cNout(cNout)
	);
end else
	illegal_option_value u_iov();

/* count dcount */
bch_decode_control #(N, K, T) u_count(
	.clk(clk),
	.reset(reset),
	.drnzero(drnzero),
	.bsel(bsel),
	.bufCe(bufCe),
	.bufkCe(bufkCe),
	.chpe(chpe),
	.msmpe(msmpe),
	.snce(snce),
	.synpe(synpe),
	.vdout(vdout),
	.vdout1(vdout1),
	.c0first(c0first),
	.cce(cce),
	.caLast(caLast),
	.cbBeg(cbBeg),
	.dringPe(dringPe),
	.cei(cei)
);

/* sN dsynN */
bch_syndrome #(M, T) u_bch_syndrome(
	.clk(clk),
	.ce(cei),
	.pe(synpe),
	.snce(snce),
	.din(din),
	.out(synN),
	.snNout(snNout)
);

chien #(M, T) u_chien(
	.clk(clk),
	.cei(cei),
	.chpe(chpe),
	.cNout(cNout),
	.err(err)
);

/* buf dbuf */
always @(posedge clk) begin
	if (bufCe)
		buf_ <= #TCQ {buf_[BUF_SIZE-2:0], bufk[K-1]};
	if (bufkCe)
		bufk <= #TCQ {bufk[K-2:0], din};
	dout <= #TCQ (buf_[BUF_SIZE-1] ^ err) && vdout1;
end

/* Debug to easily access syndromes, etc */
for (i = 1; i < 2*T; i = i + 1) begin : syn
	wire [M-1:0] syn = synN[i*M+:M];
end

for (i = 0; i < 2*T-1; i = i + 1) begin : sn_out
	wire [M-1:0] sn_out = snNout[i*M+:M];
end

for (i = 1; i < T+1; i = i + 1) begin : c_out
	wire [M-1:0] c_out = cNout[i*M+:M];
end


endmodule
