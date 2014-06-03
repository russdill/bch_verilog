`timescale 1ns / 1ps

module dec_decode #(
	parameter N = 15,
	parameter K = 5,
	parameter T = 2		/* Correctable errors */
) (
	input clk,
	input reset,
	input din,
	output reg vdout = 0,
	output reg dout = 0
);
	`include "bch.vh"

	localparam TCQ = 1;
	localparam M = n2m(N);

	wire [M-1:0] syn1;
	wire [M-1:0] ch1;
	wire pe;
	wire cef;
	wire err;
	reg vdout1 = 0;
	reg [N+1:0] buf_ = 0;
	wire [M-1:0] count;
	wire vdoutS;
	wire vdoutR;
	reg nFirst = 0;

	wire [M-1:0] syn3;
	wire [M-1:0] ch3;
	wire [M-1:0] power;
	wire neq;
	wire errcheck;
	wire err1;
	wire err2;
	reg ff1 = 0;
	reg ff3 = 0;

	assign pe = count == 1'b1; 
	assign cef = count == bch_rev(M, lpow(M, 1));
	assign vdoutS = nFirst && cef;
	assign vdoutR = reset || count == bch_rev(M, lpow(M, K + 1));

	if (T > 1) begin
		assign neq = power != ch3;
		assign err1 = ff1 && !ff3 && !neq && !(|ch1);
		assign err2 = ff1 && ff3 && !neq && |ch1;
		assign err = err1 || err2;
		assign errcheck = !cef;
	end else begin
		assign err = ch1[0] & &(~ch1[M-1:1]);
	end

	dsynN #(M, T, 0) u_syn1(
		.clk(clk),
		.ce(1'b1),
		.pe(pe),
		.din(din && !reset),
		.synN(syn1)
	);

	dch #(M, 1) u_dch1(
		.clk(clk),
		.err(T > 1 ? err : 1'b0),
		.errcheck(T > 1 ? errcheck : 1'b0),
		.ce(1'b1),
		.pe(pe),
		.in(syn1),
		.out(ch1)
	);
	if (T > 1) begin
		dsynN #(M, T, 1) u_syn3(
			.clk(clk),
			.ce(1'b1),
			.pe(pe),
			.din(din && !reset),
			.synN(syn3)
		);

		dch #(M, 3) u_dch3(
			.clk(clk),
			.err(err),
			.errcheck(errcheck),
			.ce(1'b1),
			.pe(pe),
			.in(syn3),
			.out(ch3)
		);

		pow3 #(M) u_pow3(
			.in(ch1),
			.out(power)
		);
	end

	finite_counter #(M) u_counter(
		.clk(clk),
		.reset(reset),
		.count(count)
	);

	always @(posedge clk) begin
		if (reset)
			nFirst <= #TCQ 1'b0;
		else if (vdoutR)
			nFirst <= #TCQ 1'b1;

		if (vdoutR)
			vdout1 <= #TCQ 1'b0;
		else if (vdoutS)
			vdout1 <= #TCQ 1'b1;

		vdout <= #TCQ vdout1;

		if (T > 1) begin
			if (cef || err) begin
				ff1 <= #TCQ |ch1;
				ff3 <= #TCQ neq;
			end
		end

		/* buf dbuf */
		buf_ <= #TCQ {buf_[N:0], din && !reset};
		dout <= #TCQ (buf_[N+1] ^ err) && vdout1;
	end
endmodule
