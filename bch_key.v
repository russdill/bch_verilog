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
	output errors_present,			/* Valid during start cycle */
	output [log2(T+1)-1:0] err_count,	/* Valid during done cycle */
	output busy,
	output done
);

	localparam TCQ = 1;

	if (T == 1) begin : SEC_DEC
		reg waiting = 0;
		assign sigma = {syndromes[M+:M]};
		assign err_count = start && |syndromes[M+:M];
		assign errors_present = err_count;
		assign done = start;
		assign busy = waiting && !accepted;
		always @(posedge clk)
			if (start && !accepted)
				waiting <= #TCQ 1;
			else if (accepted)
				waiting <= #TCQ 0;

	end else if (OPTION == "POW3") begin : POW3
		if (T != 2)
			pow3_only_valid_for_t_2 u_povft2();

		reg waiting = 0;
		wire [M-1:0] power;

		assign sigma = syndromes[M+:3*M];
		assign done = start;
		assign busy = waiting && !accepted;
		assign errors_present = start && (|syndromes[M+:M] || |syndromes[3*M+:M]);

		/* FIXME: Duplicated from error correcting function */
		assign err_count = start ? (|syndromes[M+:M] ?
			(power == syndromes[3*M+:M] ? 1 : 2) :
			(|syndromes[3*M+:M] ? 3 : 0)) : 0;

		pow3 #(M) u_pow3(
			.in(syndromes[M+:M]),
			.out(power)
		);

		always @(posedge clk)
			if (start && !accepted)
				waiting <= #TCQ 1;
			else if (accepted)
				waiting <= #TCQ 0;

	end else if (OPTION == "SERIAL") begin : BMA_SERIAL
		assign errors_present = start && |syndromes;	/* Candidate for pipelining */
		bch_key_bma_serial #(M, T, OPTION) u_bma (
			.clk(clk),
			.start(start),
			.syndromes(syndromes),
			.sigma(sigma),
			.done(done),
			.busy(busy),
			.accepted(accepted),
			.err_count(err_count)
		);
	end else if (OPTION == "PARALLEL") begin : BMA_PARALLEL
		assign errors_present = start && |syndromes;	/* Candidate for pipelining */
		bch_key_bma_parallel #(M, T, OPTION) u_bma (
			.clk(clk),
			.start(start),
			.syndromes(syndromes),
			.sigma(sigma),
			.done(done),
			.busy(busy),
			.accepted(accepted),
			.err_count(err_count)
		);
	end
endmodule
