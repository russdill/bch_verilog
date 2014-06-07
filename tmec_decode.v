`timescale 1ns / 1ps

module tmec_decode #(
	parameter N = 15,
	parameter K = 5,
	parameter T = 3,	/* Correctable errors */
	parameter OPTION = "SERIAL"
) (
	input clk,
	input start,
	input [2*T*M-1:M] syndromes,
	output err_start,
	output err_valid,
	output err
);

`include "bch.vh"

localparam TCQ = 1;
localparam M = n2m(N);

wire [M*(2*T-1)-1:0] syn_shuffled;
wire [2*T*M-1:M] syndromes;
wire [M*(T+1)-1:0] sigma;

wire bsel;
wire next_l;
wire d_r_nonzero;
wire ch_start;

wire syn_shuffle;
wire [log2(T)-1:0] bch_n;

bch_syndrome_shuffle #(M, T) u_bch_syndrome_shuffle(
	.clk(clk),
	.start(start),
	.ce(syn_shuffle),
	.synN(syndromes),
	.syn_shuffled(syn_shuffled)
);


if (OPTION == "PARALLEL") begin
	tmec_decode_parallel #(M, T) u_decode_parallel (
		.clk(clk),
		.start(start),
		.bsel(bsel),
		.bch_n(bch_n),
		.syn1(syndromes[1*M+:M]),
		.syn_shuffled(syn_shuffled),
		.syn_shuffle(syn_shuffle),
		.next_l(next_l),
		.done(ch_start),
		.d_r_nonzero(d_r_nonzero),
		.sigma(sigma)
	);
end else if (OPTION == "SERIAL") begin
	tmec_decode_serial #(M, T) u_decode_serial (
		.clk(clk),
		.start(start),
		.bsel(bsel),
		.bch_n(bch_n),
		.syn1(syndromes[1*M+:M]),
		.syn_shuffled(syn_shuffled),
		.syn_shuffle(syn_shuffle),
		.next_l(next_l),
		.done(ch_start),
		.d_r_nonzero(d_r_nonzero),
		.sigma(sigma)
	);
end else
	illegal_option_value u_iov();

reg [log2(T+1)-1:0] l = 0;
wire syn1_nonzero = |syndromes[1*M+:M];

counter #(T) u_bch_n_counter(
	.clk(clk),
	.reset(start),
	.ce(next_l),
	.count(bch_n)
);

assign bsel = d_r_nonzero && bch_n >= l;

always @(posedge clk)
	if (start)
		l <= #TCQ {{log2(T+1)-1{1'b0}}, syn1_nonzero};
	else if (next_l)
		if (bsel)
			l <= #TCQ 2 * bch_n - l + 1;


chien #(M, K, T) u_chien(
	.clk(clk),
	.start(ch_start),
	.sigma(sigma),
	.ready(err_start),
	.valid(err_valid),
	.err(err)
);

endmodule
