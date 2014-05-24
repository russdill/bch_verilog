`timescale 1ns / 1ps

/*
 * Double (and single) error decoding
 * Output starts at N + 3 clock cycles and ends and N + 3 + K
 */
module dec_decode #(
	parameter N = 15,
	parameter K = 5,
	parameter T = 2		/* Correctable errors */
) (
	input clk,
	input reset,
	input data_in,
	output reg output_valid = 0,
	output reg data_out = 0
);
	`include "bch.vh"

	localparam TCQ = 1;
	localparam M = n2m(N);

	wire [M-1:0] syn1;
	wire [M-1:0] ch1;
	wire start;			/* Indicates syndrome calculation start/complete */
	wire done;
	wire err;
	reg next_output_valid = 0;
	reg [N+1:0] buf_ = 0;
	wire [M-1:0] count;
	wire output_last;
	reg pipeline_hot = 0;

	wire [M-1:0] syn3;
	wire [M-1:0] ch3;
	wire [M-1:0] power;
	wire neq;
	wire errcheck;
	wire err1;
	wire err2;
	reg ff1 = 0;
	reg ff3 = 0;

	assign start = count == lfsr_count(M, 0);
	assign done = count == lfsr_count(M, 1);
	assign output_last = count == lfsr_count(M, K + 1);

	if (T > 1) begin
		assign neq = power != ch3;
		assign err1 = ff1 && !ff3 && !neq && !(|ch1);
		assign err2 = ff1 && ff3 && !neq && |ch1;
		assign err = err1 || err2;
		/* assign err == ff1 && !neq && ff3 == |ch1; */
		assign errcheck = !done;
	end else begin
		assign err = ch1 == 1;
		assign errcheck = 0;
	end

	dsynN #(M, T, 0) u_syn1(
		.clk(clk),
		.ce(1'b1),
		.start(start),
		.data_in(data_in),
		.synN(syn1)
	);

	dch #(M, 1) u_dch1(
		.clk(clk),
		.err(T > 1 ? err : 1'b0),
		.errcheck(errcheck),
		.ce(1'b1),
		.start(start),
		.in(syn1),
		.out(ch1)
	);
	if (T > 1) begin
		dsynN #(M, T, 1) u_syn3(
			.clk(clk),
			.ce(1'b1),
			.start(start),
			.data_in(data_in),
			.synN(syn3)
		);

		dch #(M, 3) u_dch3(
			.clk(clk),
			.err(err),
			.errcheck(errcheck),
			.ce(1'b1),
			.start(start),
			.in(syn3),
			.out(ch3)
		);

		pow3 #(M) u_pow3(
			.in(ch1),
			.out(power)
		);
	end

	/* Counts up to M^2-1 */
	lfsr_counter #(M) u_counter(
		.clk(clk),
		.reset(reset),
		.count(count)
	);

	always @(posedge clk) begin
		if (reset)
			pipeline_hot <= #TCQ 1'b0;
		else if (output_last)
			pipeline_hot <= #TCQ 1'b1;

		if (output_last || reset)
			next_output_valid <= #TCQ 1'b0;
		else if (pipeline_hot && done)
			next_output_valid <= #TCQ 1'b1;

		output_valid <= #TCQ next_output_valid;

		if (T > 1) begin
			if (done || err) begin
				ff1 <= #TCQ |ch1;
				ff3 <= #TCQ neq;
			end
		end

		/* buf dbuf */
		buf_ <= #TCQ {buf_[N:0], data_in && !reset};
		data_out <= #TCQ (buf_[N+1] ^ err) && next_output_valid;
	end
endmodule
