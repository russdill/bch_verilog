`timescale 1ns / 1ps

/* parallel inversionless */
module tmec_decode_parallel #(
	parameter M = 4,
	parameter T = 3		/* Correctable errors */
) (
	input clk,
	input synpe,
	input snce,
	input bsel,
	input msmpe,
	input [M-1:0] syn1,
	input [M*(2*T-1)-1:0] snNout,

	output d_r_nonzero,
	output reg [M*(T+1)-1:0] sigma = 0
);
	`include "bch.vh"

	localparam TCQ = 1;

	reg [M-1:0] dr = 0;
	wire [M-1:0] cs;
	reg [M-1:0] dp = 0;
	wire [M*(T+1)-1:0] mNout;
	wire [M*(T+1)-1:0] mbNout;
	wire [M*(T+1)-1:0] mcNout;
	reg [M*(T+1)-1:0] beta = 0;

	genvar i;

	wire [M*4-1:0] beta0;
	assign beta0 = {{M-1{1'b0}}, !syn1, {M-1{1'b0}}, |syn1, {2*M{1'b0}}};

	wire [M*2-1:0] sigma0;
	assign sigma0 = {syn1[0+:M], {M-1{1'b0}}, 1'b1};

	assign d_r_nonzero = |dr;

	/* cs generation, input rearranged_in, output cs */
	/* snNen dandm/msN doxrt */
	/* msN dxort */
	finite_parallel_adder #(M, T+1) u_generate_cs(mNout, cs);

	always @(posedge clk) begin
		/* qpd drdcesone */
		if (synpe) begin
			dp <= #TCQ syn1 ? syn1 : 1;
			sigma <= #TCQ sigma0;
			beta <= #TCQ beta0;
		end else if (snce) begin
			if (bsel)
				dp <= #TCQ dr;
			sigma <= #TCQ {mbNout ^ mcNout};
			beta[2*M+:M*(T-1)] <= #TCQ bsel ? sigma[0*M+:M*(T-1)] : beta[0*M+:M*(T-1)];
		end

		/* msm drdce */
		if (msmpe)
			dr <= #TCQ cs;
	end

	parallel_standard_multiplier #(M, T+1) u_mbn(
		.standard_in1(dr),
		.standard_in2(beta),
		.standard_out(mbNout)
	);

	for (i = 0; i <= T; i = i + 1) begin : parallel_standard_multiplier
		parallel_standard_multiplier #(M, 2) u_mn(
			.standard_in1(sigma[i*M+:M]),
			.standard_in2({snNout[i*M+:M], dp}),
			.standard_out({mNout[i*M+:M], mcNout[i*M+:M]})
		);
	end
endmodule
