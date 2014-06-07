`timescale 1ns / 1ps

/*
 * Double (and single) error decoding
 * Output starts at N + 3 clock cycles and ends and N + 3 + K
 * Takes input for N cycles, then produces output for K cycles.
 * Output cycle and input cycle can happen simultaneously.
 */
module dec_decode #(
	parameter N = 15,
	parameter K = 5,
	parameter T = 2		/* Correctable errors */
) (
	input clk,
	input start,
	input [2*T*M-1:M] syndromes,
	output err_start,
	output err_valid,
	output err
);
	`include "bch.vh"

	localparam M = n2m(N);

	wire [M*(T+1)-1:0] sigma;

	if (T == 1)
		assign sigma = {syndromes[M+:T*M]};
	else
		assign sigma = syndromes[M+:(T+1)*M];

	chien #(M, K, T) u_chien(
		.clk(clk),
		.start(start),
		.sigma(sigma),
		.ready(err_start),
		.valid(err_valid),
		.err(err)
	);
endmodule
