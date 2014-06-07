`timescale 1ns / 1ps

module bch_key #(
	parameter M = 4,
	parameter T = 3,
	parameter OPTION = "SERIAL"
) (
	input clk,
	input start,
	input accepted,
	input [2*T*M-1:M] syndromes,
	output [M*(T+1)-1:0] sigma,
	output busy,
	output done
);

	localparam TCQ = 1;

	if (T < 3) begin : SEC_DEC
		reg waiting = 0;
		assign sigma = T == 1 ? {syndromes[M+:T*M]} : syndromes[M+:(T+1)*M];
		assign done = start;
		assign busy = waiting && !accepted;
		always @(posedge clk)
			if (start && !accepted)
				waiting <= #TCQ 1;
			else if (accepted)
				waiting <= #TCQ 0;

	end else if (OPTION == "SERIAL") begin : BMA_SERIAL
		bch_key_bma_serial #(M, T, OPTION) u_bma (
			.clk(clk),
			.start(start),
			.syndromes(syndromes),
			.sigma(sigma),
			.done(done),
			.busy(busy),
			.accepted(accepted)
		);
	end else if (OPTION == "PARALLEL") begin : BMA_PARALLEL
		bch_key_bma_parallel #(M, T, OPTION) u_bma (
			.clk(clk),
			.start(start),
			.syndromes(syndromes),
			.sigma(sigma),
			.done(done),
			.busy(busy),
			.accepted(accepted)
		);
	end
endmodule
