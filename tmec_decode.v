`timescale 1ns / 1ps

module bch_key #(
	parameter M = 4,
	parameter T = 3,
	parameter OPTION = "SERIAL"
) (
	input clk,
	input start,
	input [2*T*M-1:M] syndromes,
	output [M*(T+1)-1:0] sigma,
	output done
);
	if (T == 1) begin : SEC
		assign sigma = {syndromes[M+:T*M]};
		assign done = start;
	end else if (T == 2) begin : DEC
		assign sigma = syndromes[M+:(T+1)*M];
		assign done = start;
	end else if (OPTION == "SERIAL") begin : BMA_SERIAL
		bch_key_bma_serial #(M, T, OPTION) u_bma (
			.clk(clk),
			.start(start),
			.syndromes(syndromes),
			.sigma(sigma),
			.done(done)
		);
	end else if (OPTION == "PARALLEL") begin : BMA_PARALLEL
		bch_key_bma_parallel #(M, T, OPTION) u_bma (
			.clk(clk),
			.start(start),
			.syndromes(syndromes),
			.sigma(sigma),
			.done(done)
		);
	end
endmodule
