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
module tmec_decode_serial #(
	parameter M = 4,
	parameter T = 3		/* Correctable errors */
) (
	input clk,
	input synpe,
	input snce,
	input bsel,
	input caLast,
	input cbBeg,
	input msmpe,
	input cce,
	input dringPe,
	input [M-1:0] syn1,
	input [M*(2*T-1)-1:0] snNout,

	output reg drnzero = 0,
	output [M*(T+1)-1:0] cNout /* sigma */
);

	`include "bch.vh"

	localparam TCQ = 1;

	wire [M-1:0] dr;
	wire [M-1:0] drpd;
	wire [M-1:0] dli;
	wire [M-1:0] dmIn;
	wire [T:0] cin;
	wire [M*(T+1)-1:0] sigma;
	wire [T:0] sigma_serial;		/* 0 bits of each sigma */

	reg [M*(T+1)-1:0] beta = 0;
	reg [M*(T-1)-1:0] sigma_last = 0;	/* Last sigma values */
	reg [M-1:0] qd = 0;

	wire [M*4-1:0] beta0;			/* Initial beta */
	wire [M*(T+1)-1:0] dr0;			/* Initial dr */

	/* beta(1)(x) = syn1 ? x^2 : x^3 */
	assign beta0 = {{{M-1{1'b0}}, !syn1}, {{M-1{1'b0}}, |syn1}, {(M*2){1'b0}}};

	/* dr(0) = 1 + S_1 * x */
	assign dr0 = {syn1, {(M-1){1'b0}}, 1'b1};

	assign cNout = sigma;

	always @(posedge clk) begin
		/* bN drdce */
		if (synpe) begin
			beta <= #TCQ beta0;
			sigma_last <= #TCQ beta0[2*M+:2*M];	/* beta(1) */
		end else if (caLast) begin

			/* qdrOr drdr1ce */
			drnzero <= #TCQ |dr;

			/* qdd drdce */
			qd <= #TCQ drpd;

			/* ccN drdce */
			sigma_last <= #TCQ sigma[0*M+:M*T];

			/* b^(r+1)(x) = x^2 * (bsel ? sigmal^(r-1)(x) : b_(r)(x)) */
			beta[2*M+:(T-1)*M] <= #TCQ (cbBeg || bsel) ? sigma_last[0*M+:(T-1)*M] : beta[0*M+:(T-1)*M];
		end
	end

	wire [M-1:0] denom;
	assign denom = synpe ? syn1 : dr;	/* syn1 is d_p initial value */

	/* d_rp = d_p^-1 * d_r */
	finite_divider #(M) u_dinv(
		.clk(clk),
		.start(synpe || (snce && bsel)),
		.standard_numer(dr),
		/* d_p = S_1 ? S_1 : 1 */
		.standard_denom(denom ? denom : {1'b1}),
		.dual_out(drpd)
	);

	/* d_rp -> standard basis */
	dual_to_standard #(M) u_dmli(drpd, dli);

	assign dmIn = caLast ? dli : qd;

	/* mbN SDBM d_rp * beta_i(r) */
	serial_mixed_multiplier #(M, T + 1) u_serial_mixed_multiplier(
		.clk(clk),
		.start(dringPe),
		.dual_in(dmIn),
		.standard_in(beta),
		.dual_out(cin)
	);

	/* cN dshr */
	/* Add Beta * drp to sigma (Summation) */
	/* simga_i^(r-1) + d_rp * beta_i^(r) */
	finite_serial_adder #(M) u_cN [T:0] (
		.clk(clk),
		.start(synpe),
		.ce(cce),
		.parallel_in(dr0),
		.serial_in({(T+1){!cbBeg}} & cin),
		.parallel_out(sigma),
		.serial_out(sigma_serial)
	);

	/* d_r = summation (simga_i^(r-1) + d_rp * beta_i^(r)) * S_(2 * r - i + 1) from i = 0 to t */
	serial_standard_multiplier #(M, T+1) msm_serial_standard_multiplier(
		.clk(clk), 
		.run(!caLast),
		.start(msmpe),
		.parallel_in(snNout[0+:M*(T+1)]),
		.serial_in(sigma_serial),
		.out(dr)
	);

endmodule
