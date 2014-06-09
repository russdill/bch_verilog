`timescale 1ns / 1ps

`include "bch_defs.vh"

/* Candidate for pipelining */
module bch_errors_present #(
	parameter [`BCH_PARAM_SZ-1:0] P = `BCH_SANE,
	parameter OPTION = "SERIAL"
) (
	input start,
	input [`BCH_SYNDROMES_SZ(P)-1:0] syndromes,
	output errors_present			/* Valid during start cycle */
);
	localparam M = `BCH_M(P);

	if (`BCH_T(P) == 1) begin : SEC_DEC
		assign errors_present = start && |syndromes[0+:M];
	end else if (OPTION == "POW3") begin : POW3
		if (`BCH_T(P) != 2)
			pow3_only_valid_for_t_2 u_povft2();
		assign errors_present = start && (|syndromes[0+:M] || |syndromes[2*M+:M]);
	end else begin : BMA
		assign errors_present = start && |syndromes;
	end
endmodule


module bch_key #(
	parameter [`BCH_PARAM_SZ-1:0] P = `BCH_SANE,
	parameter OPTION = "SERIAL"
) (
	input clk,
	input start,
	input accepted,
	input [`BCH_SYNDROMES_SZ(P)-1:0] syndromes,
	output [`BCH_SIGMA_SZ(P)-1:0] sigma,
	output [`BCH_ERR_SZ(P)-1:0] err_count,	/* Valid during done cycle */
	output busy,
	output done
);
	`include "bch.vh"

	localparam TCQ = 1;
	localparam M = `BCH_M(P);

	if (`BCH_T(M) == 1) begin : SEC_DEC
		reg waiting = 0;
		assign sigma = {syndromes[0+:M]};
		assign err_count = start && |syndromes[0+:M];
		assign done = start;
		assign busy = waiting && !accepted;
		always @(posedge clk)
			if (start && !accepted)
				waiting <= #TCQ 1;
			else if (accepted)
				waiting <= #TCQ 0;

	end else if (OPTION == "POW3") begin : POW3
		if (`BCH_T(P) != 2)
			pow3_only_valid_for_t_2 u_povft2();

		reg waiting = 0;
		wire [M-1:0] power;

		assign sigma = syndromes[0+:3*M];
		assign done = start;
		assign busy = waiting && !accepted;

		/* FIXME: Duplicated from error correcting function */
		assign err_count = start ? (|syndromes[0+:M] ?
			(power == syndromes[2*M+:M] ? 1 : 2) :
			(|syndromes[2*M+:M] ? 3 : 0)) : 0;

		pow3 #(M) u_pow3(
			.in(syndromes[0+:M]),
			.out(power)
		);

		always @(posedge clk)
			if (start && !accepted)
				waiting <= #TCQ 1;
			else if (accepted)
				waiting <= #TCQ 0;

	end else if (OPTION == "SERIAL") begin : BMA_SERIAL
		bch_key_bma_serial #(P) u_bma (
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
		bch_key_bma_parallel #(P) u_bma (
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
