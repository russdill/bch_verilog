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
	wire [M-1:0] qdpin;
	reg [M-1:0] dp = 0;
	wire [M*(T+1)-1:0] mNout;
	wire [M*(T+1)-1:1*M] cNin;
	wire [M*(T+1)-1:2*M] mbNout;
	wire [M*(T+1)-1:0] mcNout;
	reg [M*(T+1)-1:M*2] bNout = 0;

	wire qdpce;
	wire qdpset;
	wire b23set;
	wire b2s;
	wire b3s;

	genvar i;

	assign qdpce = snce && (bsel || (d_r_nonzero && synpe));
	assign qdpset = synpe && !d_r_nonzero;
	assign qdpin = synpe ? syn1 : dr;

	assign d_r_nonzero = |qdpin;
	assign b23set = synpe || (snce && !bsel);
	assign b2s = synpe && d_r_nonzero;
	assign b3s = synpe && !d_r_nonzero;

	/* xc1 dmul21 */
	/* csN dxorm */
	assign cNin = {mbNout ^ mcNout[2*M+:M*(T-1)], synpe ? syn1[0+:M] : mcNout[1*M+:M]};

	/* cs generation, input rearranged_in, output cs */
	/* snNen dandm/msN doxrt */
	/* msN dxort */
	finite_parallel_adder #(M, T+1) u_generate_cs(mNout, cs);

	always @(posedge clk) begin
		/* qpd drdcesone */
		if (qdpset)
			dp <= #TCQ 1;
		else if (qdpce)
			dp <= #TCQ qdpin;

		/* msm drdce */
		if (msmpe)
			dr <= #TCQ cs;

		/* c0 drdcesone */
		/* cN drdcer */
		if (synpe)
			sigma <= #TCQ {cNin[1*M+:M], {M-1{1'b0}}, 1'b1};
		else if (snce)
			sigma <= #TCQ {cNin, mcNout[0*M+:M]};

		/* b2 drdcesone */
		if (b23set) begin
			bNout[2*M+:M*2] <= #TCQ {{M-1{1'b0}}, b3s, {M-1{1'b0}}, b2s};
		end else if (snce)
			bNout[2*M+:M*2] <= #TCQ sigma[0*M+:M*2];
	end

	parallel_standard_multiplier #(M, T - 1) u_mbn(
		.standard_in1(dr),
		.standard_in2(bNout),
		.standard_out(mbNout)
	);

	for (i = 0; i <= T; i = i + 1) begin : parallel_standard_multiplier
		parallel_standard_multiplier #(M, 2) u_mn(
			.standard_in1(sigma[i*M+:M]),
			.standard_in2({snNout[i*M+:M], dp}),
			.standard_out({mNout[i*M+:M], mcNout[i*M+:M]})
		);
	end

	generate
		/* bN drdcer */
		if (T >= 3) begin : bN_drdcer
			always @(posedge clk) begin
				if (synpe)
					bNout[4*M+:M*(T-3)] <= #TCQ 0;
				else if (snce)
					bNout[4*M+:M*(T-3)] <= bsel ? sigma[2*M+:M*(T-3)] : bNout[2*M+:M*(T-3)];
			end
		end
	endgenerate
endmodule
