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
	input c0first,
	input [M-1:0] syn1,
	input [M*(2*T-1)-1:0] snNout,

	output drnzero,
	output [M*(T+1)-1:0] cNout /* sigma */
);

	`include "bch.vh"

	localparam TCQ = 1;

	wire [M-1:0] dr;
	wire [M-1:0] dra;
	wire [M-1:0] drpd;
	wire [M-1:0] dli;
	wire [M-1:0] dmIn;
	wire [M-1:0] c1in;
	wire [T:1] cin;
	wire [T:1] cNbits;

	reg [M*(T+1)-1:M*2] beta = 0;
	reg [M*(T-1)-1:M*2] ccNout = 0;
	reg [M-1:0] qd = 0;

	wire b2ce;
	wire b3ce;
	wire b3set;
	wire b3sIn;
	wire b4sIn;
	wire xbsel;
	wire ccCe;
	reg qdr_or = 0;

	genvar i;

	assign cNout[0+:M] = 1;

	/* beta_1 is always 0 */
	assign cin[1] = 0;

	assign drnzero = synpe ? |dra : qdr_or;

	/* xdr dmul21 */
	assign dra = synpe ? syn1 : dr;
	assign xbsel = bsel || cbBeg;
	assign ccCe = (msmpe && cbBeg) || caLast;

	always @(posedge clk) begin
		/* qdrOr drdr1ce */
		if (synpe || caLast)
			qdr_or <= #TCQ |dra;

		/* qdd drdce */
		if (caLast)
			qd <= #TCQ drpd;

		/* b^(r+1)(x) = x^2 * (bsel ? sigmal^(r-1)(x) : b_(r)(x)) */
		/* bN drdce */
		if (synpe) begin
			beta[2*M+:M] <= #TCQ cNout[0*M+:M];
			beta[3*M+:M] <= #TCQ {{M-1{1'b0}}, !drnzero};
		end else if (caLast) begin
			if (cbBeg) begin
				if (T >= 4)
					beta[4*M+:M*(T-3)] <= #TCQ ccNout[2*M+:M*(T-3)];
			end else begin
				beta[2*M+:M] <= #TCQ bsel ? cNout[0*M+:M] : {M{1'b0}};
				beta[3*M+:M] <= #TCQ bsel ? cNout[1*M+:M] : {M{1'b0}};
				if (T >= 4)
					beta[4*M+:M*(T-3)] <= #TCQ bsel ? ccNout[2*M+:M*(T-3)] : beta[2*M+:M*(T-3)];
			end
		end

		/* ccN drdce */
		if (ccCe)
			ccNout[2*M+:M*(T-3)] <= #TCQ cNout[2*M+:M*(T-2)];
	end

	finite_divider #(M) u_dinv(
		.clk(clk),
		.reset(synpe && !(snce && bsel)),
		.start(((snce && bsel) || synpe) && (bsel || (drnzero && cbBeg))),
		.standard_numer(dra),
		.standard_denom(dra),
		.dual_out(drpd)
	);

	/* d_rp -> standard basis */
	dual_to_standard #(M) u_dmli(drpd, dli);

	assign dmIn = caLast ? dli : qd;

	/* mbN SDBM d_rp * beta_i(r) */
	serial_mixed_multiplier #(M, T - 1) u_serial_mixed_multiplier(
		.clk(clk),
		.start(dringPe),
		.dual_in(dmIn),
		.standard_in(beta[2*M+:(T-1)*M]),
		.dual_out(cin[2+:(T-1)])
	);

	/* cN dshr */
	/* Add Beta * drp to sigma (Summation) */
	/* simga_i^(r-1) + d_rp * beta_i^(r) */
	/* Initial value 1 + S_1 * x */
	finite_serial_adder #(M) u_cN [T-1:0] (
		.clk(clk),
		.start(synpe),
		.ce(cce),
		.parallel_in({{M*(T-1){1'b0}}, syn1}),
		.serial_in({T{!cbBeg}} & cin[1+:T]),
		.parallel_out(cNout[M+:M*T]),
		.serial_out(cNbits[1+:T])
	);

	/* d_r = summation (simga_i^(r-1) + d_rp * beta_i^(r)) * S_(2 * r - i + 1) from i = 0 to t */
	serial_standard_multiplier #(M, T+1) msm_serial_standard_multiplier(
		.clk(clk), 
		.run(!caLast),
		.start(msmpe),
		.parallel_in(snNout[0+:M*(T+1)]),
		.serial_in({cNbits, c0first}),
		.out(dr)
	);

endmodule
