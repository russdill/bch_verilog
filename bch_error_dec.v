`timescale 1ns / 1ps

`include "bch_defs.vh"

/* Supports double and single bit errors */
module bch_error_dec #(
	parameter [`BCH_PARAM_SZ-1:0] P = `BCH_SANE
) (
	input clk,
	input start,					/* Latch inputs, start calculating */
	input [`BCH_SYNDROMES_SZ(P)-1:0] syndromes,
	input accepted,
	output reg [`BCH_ERR_SZ(P)-1:0] err_count = 0,	/* Valid during valid cycles */
	output busy,
	output ready,					/* First valid output data */
	output valid,					/* Outputting data */
	output err
);
	`include "bch.vh"

	localparam TCQ = 1;
	localparam M = `BCH_M(P);
	localparam T = `BCH_T(P);

	wire [(2*T-1)*M-1:0] expanded;
	wire [`BCH_SIGMA_SZ(P)-1:0] sigma;
	wire [`BCH_SIGMA_SZ(P)-1:0] chien;

	bch_syndrome_expand #(P) u_expand(
		.syndromes(syndromes),
		.expanded(expanded)
	);

	assign sigma = expanded;

	bch_chien #(P) u_chien(
		.clk(clk),
		.sigma(sigma),
		.err_feedback(err),
		.start(start),
		.chien(chien),
		.accepted(accepted),
		.busy(busy),
		.ready(ready),
		.valid(valid)
	);

	if (T == 1) begin : SEC
		/*
		 * SEC sigma(x) = 1 + S_1 * x
		 * No error if S_1 = 0
		 */
		assign err = chien[0+:`BCH_M(P)] == 1;
		always @(posedge clk)
			if (start)
				err_count <= #TCQ |syndromes;

	end else if (T == 2) begin : POW3
		/*
		 * DEC simga(x) = 1 + sigma_1 * x + sigma_2 * x^2 =
		 *		1 + S_1 * x + (S_1^2 + S_3 * S_1^-1) * x^2
		 * No  error  if S_1  = 0, S_3  = 0
		 * one error  if S_1 != 0, S_3  = S_1^3
		 * two errors if S_1 != 0, S_3 != S_1^3
		 * >2  errors if S_1  = 0, S_3 != 0
		 * The below may be a better choice for large circuits (cycles tradeoff)
		 * sigma_1(x) = S_1 + S_1^2 * x + (S_1^3 + S_3) * x^2
		 */
		wire [M-1:0] ch1_flipped;
		wire [M-1:0] ch3_flipped;

		wire [M-1:0] power;
		reg [1:0] errors_last = 0;
		wire [1:0] errors;

		/* For each cycle, try flipping the bit */
		assign ch1_flipped = z[M*0+:M] ^ !first_cycle;
		assign ch3_flipped = z[M*2+:M] ^ !first_cycle;

		pow3 #(M) u_pow3(
			.in(ch1_flipped),
			.out(power)
		);

		/* Calculate the number of erros */
		assign errors = |ch1_flipped ?
			(power == ch3_flipped ? 1 : 2) :
			(|ch3_flipped ? 3 : 0);
		/*
		 * If flipping reduced the number of errors,
		 * then we found an error
		 */
		assign err = errors_last > errors;

		always @(posedge clk) begin

			/*
			 * Load the new error count on cycle zero or when
			 * we find an error
			 */
			if (start)
				errors_last <= #TCQ 0;
			else if (first_cycle || err)
				errors_last <= #TCQ errors;

			if (accepted)
				first_cycle <= #TCQ start;
			if (first_cycle)
				err_count <= #TCQ errors;
		end

	end else
		dec_only_valid_for_t_less_than_3 u_dovftlt3();
endmodule
