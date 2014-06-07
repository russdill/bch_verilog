`timescale 1ns / 1ps

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
module bch_key_bma_serial #(
	parameter M = 4,
	parameter T = 3		/* Correctable errors */
) (
	input clk,
	input start,
	input [2*T*M-1:M] syndromes,

	output reg done = 0,
	output [M*(T+1)-1:0] sigma
);
	`include "bch.vh"

	localparam TCQ = 1;

	wire [M-1:0] d_r;
	wire [M-1:0] d_rp_dual;
	wire [T:0] cin;
	wire [T:0] sigma_serial;		/* 0 bits of each sigma */
	wire [M-1:0] syn1 = syndromes[M+:M];

	reg [M*(T+1)-1:0] beta = 0;
	reg [M*(T-1)-1:0] sigma_last = 0;	/* Last sigma values */
	reg adder_ce = 0;

	reg first_cycle = 0;
	reg second_cycle = 0;
	reg penult2_cycle = 0;
	reg penult1_cycle = 0;
	reg last_cycle = 0;

	reg first_calc = 0;	/* bch_n == 0 */
	reg final_calc = 0;	/* bch_n == T - 1 */
	reg counting = 0;

	/* beta(1)(x) = syn1 ? x^2 : x^3 */
	wire [M*4-1:0] beta0;			/* Initial beta */
	assign beta0 = {{{M-1{1'b0}}, !syn1}, {{M-1{1'b0}}, |syn1}, {(M*2){1'b0}}};

	/* d_r(0) = 1 + S_1 * x */
	wire [M*(T+1)-1:0] d_r0;		/* Initial dr */
	assign d_r0 = {syn1, {(M-1){1'b0}}, 1'b1};

	wire [log2(T)-1:0] bch_n;
	counter #(T) u_bch_n_counter(
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

	wire [M*(2*T-1)-1:0] syn_shuffled;
	bch_syndrome_shuffle #(M, T) u_bch_syndrome_shuffle(
		.clk(clk),
		.start(start),
		.ce(last_cycle),
		.synN(syndromes),
		.syn_shuffled(syn_shuffled)
	);

	reg d_r_nonzero = 0;
	wire bsel;
	reg [log2(T+1)-1:0] l = 0;
	assign bsel = d_r_nonzero && bch_n >= l;

	always @(posedge clk) begin
		if (start)
			l <= #TCQ {{log2(T+1)-1{1'b0}}, |syn1};
		else if (last_cycle)
			if (bsel)
				l <= #TCQ 2 * bch_n - l + 1;

		if (last_cycle || start)
			adder_ce <= #TCQ 1;
		else if (done || penult2_cycle)
			adder_ce <= #TCQ 0;

		if (last_cycle || start)
			final_calc <= #TCQ bch_n == T - 2;

		if (start)
			first_calc <= #TCQ 1;
		else if (last_cycle)
			first_calc <= #TCQ 0;

		if (start) begin
			beta <= #TCQ beta0;
			sigma_last <= #TCQ beta0[2*M+:2*M];	/* beta(1) */
		end else if (last_cycle) begin
			d_r_nonzero <= #TCQ |d_r;
			sigma_last <= #TCQ sigma[0*M+:M*T];

			/* b^(r+1)(x) = x^2 * (bsel ? sigmal^(r-1)(x) : b_(r)(x)) */
			beta[2*M+:(T-1)*M] <= #TCQ (first_calc || bsel) ? sigma_last[0*M+:(T-1)*M] : beta[0*M+:(T-1)*M];
		end

		penult2_cycle <= #TCQ counting && count == M - 4;
		penult1_cycle <= #TCQ penult2_cycle && !final_calc;
		last_cycle <= #TCQ penult1_cycle;
		first_cycle <= #TCQ last_cycle;
		second_cycle <= #TCQ first_cycle || start;
		done <= #TCQ penult2_cycle && final_calc;
		if (second_cycle)
			counting <= #TCQ 1;
		else if (count == M - 4)
			counting <= #TCQ 0;
	end

	wire [M-1:0] denom;
	assign denom = start ? syn1 : d_r;	/* syn1 is d_p initial value */

	/* d_rp = d_p^-1 * d_r */
	finite_divider #(M) u_dinv(
		.clk(clk),
		.start(start || (first_cycle && bsel)),
		.standard_numer(d_r),
		/* d_p = S_1 ? S_1 : 1 */
		.standard_denom(denom ? denom : {1'b1}),
		.dual_out(d_rp_dual)
	);

	/* mbN SDBM d_rp * beta_i(r) */
	serial_mixed_multiplier #(M, T + 1) u_serial_mixed_multiplier(
		.clk(clk),
		.start(last_cycle),
		.dual_in(d_rp_dual),
		.standard_in(beta),
		.standard_out(cin)
	);

	/* Add Beta * drp to sigma (Summation) */
	/* simga_i^(r-1) + d_rp * beta_i^(r) */
	finite_serial_adder #(M) u_cN [T:0] (
		.clk(clk),
		.start(start),
		.ce(adder_ce),
		.parallel_in(d_r0),
		.serial_in({(T+1){bch_n ? 1'b1 : 1'b0}} & cin),
		.parallel_out(sigma),
		.serial_out(sigma_serial)
	);

	/* d_r = summation (simga_i^(r-1) + d_rp * beta_i^(r)) * S_(2 * r - i + 1) from i = 0 to t */
	serial_standard_multiplier #(M, T+1) msm_serial_standard_multiplier(
		.clk(clk), 
		.run(!last_cycle),
		.start(second_cycle),
		.parallel_in(syn_shuffled[0+:M*(T+1)]),
		.serial_in(sigma_serial),
		.out(d_r)
	);
endmodule
