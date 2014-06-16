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
	assign errors_present = start && |syndromes;
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

	wire [(2*`BCH_T(P)-1)*M-1:0] expanded;

	bch_syndrome_expand #(P) u_expand(
		.syndromes(syndromes),
		.expanded(expanded)
	);

	if (`BCH_T(P) == 1) begin : SEC_DEC
		assign err_count = |syndromes;
		assign sigma = syndromes;
		assign busy = start && !accepted;
		assign done = start;

	end else if (OPTION == "POW3") begin : POW3
		if (`BCH_T(P) != 2)
			pow3_only_valid_for_t_2 u_povft2();

		wire [M-1:0] power;

		assign sigma = expanded[0+:3*M];
		assign busy = start && !accepted;
		assign done = start;

		/* FIXME: Duplicated from error correcting function */
		assign err_count = start ? (|expanded[0+:M] ?
			(power == expanded[2*M+:M] ? 1 : 2) :
			(|expanded[2*M+:M] ? 3 : 0)) : 0;

		pow3 #(M) u_pow3(
			.in(expanded[0+:M]),
			.out(power)
		);

	end else if (OPTION == "SERIAL") begin : BMA_SERIAL
		bch_key_bma_serial #(P) u_bma (
			.clk(clk),
			.start(start && !busy),
			.syndromes(expanded),
			.sigma(sigma),
			.done(done),
			.busy(busy),
			.accepted(accepted),
			.err_count(err_count)
		);
	end else if (OPTION == "PARALLEL") begin : BMA_PARALLEL
		bch_key_bma_parallel #(P) u_bma (
			.clk(clk),
			.start(start && !busy),
			.syndromes(expanded),
			.sigma(sigma),
			.done(done),
			.busy(busy),
			.accepted(accepted),
			.err_count(err_count)
		);
	end
endmodule
