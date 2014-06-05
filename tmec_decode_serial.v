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

	reg [M*(T+1)-1:M*2] bNout = 0;	/* Beta */
	reg [M*(T-1)-1:M*2] ccNout = 0;
	reg [M-1:0] qd = 0;

	wire b2ce;
	wire b3ce;
	wire b3set;
	wire b4set;
	wire b3sIn;
	wire b4sIn;
	wire xbsel;
	wire ccCe;
	reg qdr_or = 0;

	genvar i;

	assign cNout[0+:M] = 1;
	assign b2ce = synpe || b3ce;
	assign b3ce = caLast && !cbBeg;

	assign drnzero = synpe ? |dra : qdr_or;

	/* xdr dmul21 */
	assign dra = synpe ? syn1 : dr;

	assign b3set = synpe || (b3ce && !bsel);
	assign b3sIn = synpe && !drnzero;
	if (T > 3) begin
		assign b4set = caLast && !bsel;
		assign b4sIn = !cbBeg && bNout[2*M];
	end
	assign xbsel = bsel || cbBeg;
	assign ccCe = (msmpe && cbBeg) || caLast;

	/* beta_1 is always 0 */
	assign cin[1] = 0;

	always @(posedge clk) begin
		/* qdrOr drdr1ce */
		if (synpe || caLast)
			qdr_or <= #TCQ |dra;

		/* qdd drdce */
		if (caLast)
			qd <= #TCQ drpd;

		/* b2 drd1ce */
		if (b2ce)
			bNout[2*M] <= #TCQ bsel;

		/* drdcesone b3 */
		if (b3set)
			bNout[3*M+:M] <= #TCQ {{M-1{1'b0}}, b3sIn};
		else if (b3ce)
			bNout[3*M+:M] <= #TCQ cNout[1*M+:M];

		if (T > 3) begin
			/* b4 drdceSOne */
			if (b4set)
				bNout[4*M+:M] <= #TCQ {{M-1{1'b0}}, b4sIn};
			else if (caLast)
				bNout[4*M+:M] <= #TCQ ccNout[2*M+:M];
		end

		/* bN drdce */
		if (T >= 5)
			if (caLast)				/* bNin, xbN dmul21 */
				bNout[5*M+:M*(T-4)] <= #TCQ xbsel ? ccNout[3*M+:M*(T-4)] : bNout[3*M+:M*(T-4)];

		/* ccN drdce */
		if (ccCe)
			ccNout <= #TCQ cNout[2*M+:M*(T-2)];
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
		.standard_in(bNout[2*M+:(T-1)*M]),
		.dual_out(cin[2+:(T-1)])
	);

	/* cN dshr */
	/* Add Beta * drp to sigma (Summation) */
	/* simga_i^(r-1) + d_rp * beta_i^(r) */
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
