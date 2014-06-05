`timescale 1ns / 1ps

/*
 * Double (and single) error decoding
 * Output starts at N + 3 clock cycles and ends and N + 3 + K
 *
 * SEC sigma(x) = 1 + S_1 * x
 * No error if S_1 = 0
 *
 * DEC simga(x) = 1 + signma_1 * x + sigma_2 * x^2 =
 *		1 + S_1 * x + (S_1^2 + S_3 * S_1^-1) * x^2
 * No  error  if S_1  = 0, S_3  = 0
 * one error  if S_1 != 0, S_3  = S_1^3
 * two errors if S_1 != 0, S_3 != S_1^3
 * >2  errors if S_1  = 0, S_3 != 0
 * The below may be a better choice for large circuits (cycles tradeoff)
 * sigma_1(x) = S_1 + S_1^2 * x + (S_1^3 + S_3) * x^2
 *
 * Takes input for N cycles, then produces output for K cycles.
 * Output cycle and input cycle can happen simultaneously.
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

	wire [2*T*M-1:M] synN;
	wire [M-1:0] ch1;
	wire [M-1:0] ch1_flipped;
	wire start;			/* Indicates syndrome calculation start/complete */
	reg first = 0;			/* First output cycle */
	wire err;			/* The current output bit needs to be flipped */
	reg next_output_valid = 0;
	reg [N+1:0] buf_ = 0;
	wire [M-1:0] count;
	wire output_last;
	reg pipeline_hot = 0;

	wire [M-1:0] ch3;
	wire [M-1:0] ch3_flipped;
	wire [M-1:0] power;
	reg [1:0] errors_last = 0;
	wire [1:0] errors;

	assign start = count == lfsr_count(M, 0);
	assign output_last = count == lfsr_count(M, K + 1);

	if (T > 1) begin
		/* For each cycle, try flipping the bit */
		assign ch1_flipped = ch1 ^ !first;
		assign ch3_flipped = ch3 ^ !first;
		/*
		 * If flipping reduced the number of errors,
		 * then we found an error
		 */
		assign err = errors_last > errors;
	end else
		assign err = ch1 == 1;

	/* sN dsynN */
	bch_syndrome #(M, T) u_bch_syndrome(
		.clk(clk),
		.syn_ce(1'b1),
		.start(start),
		.din(data_in),
		.out(synN)
	);

	dch #(M, 1) u_dch1(
		.clk(clk),
		.err(err),
		.ce(1'b1),
		.start(start),
		.in(synN[1*M+:M]),
		.out(ch1)
	);
	if (T > 1) begin
		assign errors = |ch1_flipped ?
			(power == ch3_flipped ? 1 : 2) :
			(|ch3_flipped ? 3 : 0);

		dch #(M, 3) u_dch3(
			.clk(clk),
			.err(err),
			.ce(1'b1),
			.start(start),
			.in(synN[3*M+:M]),
			.out(ch3)
		);

		pow3 #(M) u_pow3(
			.in(ch1_flipped),
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
		else if (pipeline_hot && first)
			next_output_valid <= #TCQ 1'b1;

		first <= #TCQ start;
		output_valid <= #TCQ next_output_valid;

		if (T > 1) begin
			/*
			 * Load the new error count on cycle zero or when
			 * we find an error
			 */
			if (first || err)
				errors_last <= #TCQ errors;
		end

		/* buf dbuf */
		buf_ <= #TCQ {buf_[N:0], data_in && !reset};
		data_out <= #TCQ (buf_[N+1] ^ err) && next_output_valid;
	end
endmodule
