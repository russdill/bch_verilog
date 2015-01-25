/*
 * BCH Encode/Decoder Modules
 *
 * Copyright 2014 - Russ Dill <russ.dill@asu.edu>
 * Distributed under 2-clause BSD license as contained in COPYING file.
 */
`timescale 1ns / 1ps

`include "bch_defs.vh"

/*
 * serial with inversion
 * Berlekamp–Massey algorithm
 *
 * sigma_i^(r) = sigma_i^(r-1) + d_rp * beta_i^(r) (i = 1 to t-1)
 * d_r = summation sigma_i^(r) * S_(2 * r - i + 1) from i = 0 to t
 * d_rp = d_p^-1 * d_r
 *
 * combine above equations:
 * d_r = summation (simga_i^(r-1) + d_rp * beta_i^(r)) * S_(2 * r - i + 1) from i = 0 to t
 */
module bch_sigma_bma_serial #(
	parameter [`BCH_PARAM_SZ-1:0] P = `BCH_SANE
) (
	input clk,
	input start,
	input [`BCH_SYNDROMES_SZ(P)-1:0] syndromes,
	input ack_done,

	output reg done = 0,
	output ready,
	output [`BCH_SIGMA_SZ(P)-1:0] sigma,
	output reg [`BCH_ERR_SZ(P)-1:0] err_count = 0
);
	`include "bch.vh"

	localparam TCQ = 1;
	localparam M = `BCH_M(P);
	localparam T = `BCH_T(P);

	wire [M-1:0] d_r;
	wire [M-1:0] d_rp_dual;
	wire [T:0] cin;
	wire [T:0] sigma_serial;		/* 0 bits of each sigma */
	wire [M-1:0] syn1 = syndromes[0+:M];
	wire [T*M-1:0] _sigma;
	wire [M-1:0] sigma_1;

	/* because of inversion, sigma0 is always 1 */
	assign sigma = {_sigma, {M-1{1'b0}}, 1'b1};

	reg [(T+1)*M-1:0] beta = 0;
	reg [(T-1)*M-1:0] sigma_last = 0;	/* Last sigma values */

	reg first_cycle = 0;
	reg second_cycle = 0;
	reg penult2_cycle = 0;
	reg penult1_cycle = 0;
	reg last_cycle = 0;

	reg first_calc = 0;	/* bch_n == 0 */
	reg final_calc = 0;	/* bch_n == T - 1 */
	reg counting = 0;
	reg busy = 0;

	/* beta(1)(x) = syn1 ? x^2 : x^3 */
	wire [M*4-1:0] beta0;			/* Initial beta */
	assign beta0 = {{{M-1{1'b0}}, !syn1}, {{M-1{1'b0}}, |syn1}, {(M*2){1'b0}}};

	/* d_r(0) = 1 + S_1 * x */
	wire [(T+1)*M-1:0] d_r0;		/* Initial dr */
	assign d_r0 = {syn1, {(M-1){1'b0}}, 1'b1};

	wire [`BCH_ERR_SZ(P)-1:0] bch_n;
	counter #(T+1) u_bch_n_counter(
		.clk(clk),
		.reset(start),
		.ce(last_cycle),
		.count(bch_n)
	);

	wire [log2(M-4)-1:0] count;
	counter #(M-4) u_counter(
		.clk(clk),
		.reset(second_cycle),
		.ce(counting),
		.count(count)
	);

	wire [(2*T-1)*M-1:0] syn_shuffled;
	bch_syndrome_shuffle #(P) u_bch_syndrome_shuffle(
		.clk(clk),
		.start(start),
		.ce(last_cycle),
		.syndromes(syndromes),
		.syn_shuffled(syn_shuffled)
	);

	reg d_r_nonzero = 0;
	wire bsel;
	assign bsel = d_r_nonzero && bch_n >= err_count;
	reg bsel_last = 0;

	assign ready = !busy && (!done || ack_done);

	always @(posedge clk) begin
		if (start)
			busy <= #TCQ 1;
		else if (penult2_cycle && final_calc)
			busy <= #TCQ 0;

		if (penult2_cycle && final_calc)
			done <= #TCQ 1;
		else if (ack_done)
			done <= #TCQ 0;

		if (last_cycle || start)
			final_calc <= #TCQ T == 2 ? first_calc : (bch_n == T - 2);

		if (start)
			first_calc <= #TCQ 1;
		else if (last_cycle)
			first_calc <= #TCQ 0;

		if (start) begin
			beta <= #TCQ beta0;
			sigma_last <= #TCQ beta0[2*M+:2*M];	/* beta(1) */
			err_count <= #TCQ {{`BCH_ERR_SZ(P)-1{1'b0}}, |syn1};
			bsel_last <= #TCQ 1'b1;
		end else if (first_cycle) begin
			if (bsel)
				err_count <= #TCQ 2 * bch_n - err_count + 1;
			bsel_last <= #TCQ bsel;
		end else if (last_cycle) begin
			d_r_nonzero <= #TCQ |d_r;
			sigma_last <= #TCQ sigma[0+:(T-1)*M];

			/* b^(r+1)(x) = x^2 * (bsel ? sigmal^(r-1)(x) : b_(r)(x)) */
			beta[2*M+:(T-1)*M] <= #TCQ bsel_last ?
				sigma_last[0*M+:(T-1)*M] :
				beta[0*M+:(T-1)*M];
		end

		penult2_cycle <= #TCQ counting && count == M - 4;
		penult1_cycle <= #TCQ penult2_cycle && !final_calc;
		last_cycle <= #TCQ penult1_cycle;
		first_cycle <= #TCQ last_cycle;
		second_cycle <= #TCQ first_cycle || start;
		if (second_cycle)
			counting <= #TCQ 1;
		else if (count == M - 4)
			counting <= #TCQ 0;
	end

	wire [M-1:0] d_p0 = syn1 ? syn1 : 1;

	/* d_rp = d_p^-1 * d_r */
	finite_divider #(M) u_dinv(
		.clk(clk),
		.start(start || (first_cycle && bsel && !final_calc)),
		.busy(),
		.standard_numer(d_r),
		/* d_p = S_1 ? S_1 : 1 */
		.standard_denom(start ? d_p0 : d_r),	/* syn1 is d_p initial value */
		.dual_out(d_rp_dual)
	);

	/* mbN SDBM d_rp * beta_i(r) */
	serial_mixed_multiplier_dss #(M, T + 1) u_serial_mixed_multiplier(
		.clk(clk),
		.start(last_cycle),
		.dual_in(d_rp_dual),
		.standard_in(beta),
		.standard_out(cin)
	);

	/* Add Beta * drp to sigma (Summation) */
	/* sigma_i^(r-1) + d_rp * beta_i^(r) */
	wire [T:0] _cin = first_calc ? {T+1{1'b0}} : cin;
	finite_serial_adder #(M) u_cN [T:0] (
		.clk(clk),
		.start(start),
		.ce(!last_cycle && !penult1_cycle),
		.parallel_in(d_r0),
		.serial_in(_cin),	/* First time through, we just shift out d_r0 */
		.parallel_out({_sigma, sigma_1}),
		.serial_out(sigma_serial)
	);

	/* d_r = summation (sigma_i^(r-1) + d_rp * beta_i^(r)) * S_(2 * r - i + 1) from i = 0 to t */
	serial_standard_multiplier #(M, T+1) msm_serial_standard_multiplier(
		.clk(clk), 
		.reset(start || first_cycle),
		.ce(!last_cycle),
		.parallel_in(syn_shuffled[0+:M*(T+1)]),
		.serial_in(sigma_serial),
		.out(d_r)
	);

endmodule
