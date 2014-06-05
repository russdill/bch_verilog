`timescale 1ns / 1ps

/* parallel inversionless */
module bch_decode_parallel #(
	parameter M = 4,
	parameter T = 3		/* Correctable errors */
) (
	input clk,
	input synpe,
	input snce,
	input bsel,
	input msmpe,
	input chpe,
	input [M-1:0] syn1,
	input [M*(2*T-1)-1:0] snNout,

	output drnzero,
	output reg [M*(T+1)-1:0] cNout = 0
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
	reg [M*(T+1)-1:0] chNout = 0;

	wire qdpce;
	wire qdpset;
	wire b23set;
	wire b2s;
	wire b3s;

	genvar i;

	assign qdpce = bsel && snce;
	assign qdpset = synpe && !drnzero;
	assign qdpin = synpe ? syn1 : dr;

	/* xc1 dmul21 */
	assign cNin[1*M+:M] = synpe ? syn1[0+:M] : mcNout[1*M+:M];
	assign drnzero = |qdpin;
	assign b23set = synpe || (snce && !bsel);
	assign b2s = synpe && drnzero;
	assign b3s = synpe && !drnzero;

	/* csN dxorm */
	for (i = 2; i <= T; i = i + 1) begin : dxorm
		assign cNin[i*M+:M] = mbNout[i*M+:M] ^ mcNout[i*M+:M];
	end

	generate_cs #(M, T) u_generate_cs(mNout, cs);

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
		if (synpe)
			cNout[0*M+:M] <= #TCQ 1;
		else if (snce)
			cNout[0*M+:M] <= #TCQ mcNout[0*M+:M];

		/* ch0 drdce FIXME: In chien search?*/
		if (chpe)
			chNout[0*M+:M] <= #TCQ cNout[0*M+:M];

		/* c1 drdce */
		if (snce)
			cNout[1*M+:M] <= #TCQ cNin[1*M+:M];
		
		/* b2 drdcesone */
		if (b23set) begin
			bNout[2*M+:M] <= #TCQ {{M-1{1'b0}}, b2s};
			bNout[3*M+:M] <= #TCQ {{M-1{1'b0}}, b3s};
		end else if (snce) begin
			bNout[2*M+:M] <= #TCQ cNout[0*M+:M];
			bNout[3*M+:M] <= #TCQ cNout[1*M+:M];
		end
	end

	for (i = 0; i <= T; i = i + 1) begin : dpm
		dpm #(M) u_mn(
			.in1(cNout[i*M+:M]),
			.in2(snNout[i*M+:M]),
			.out(mNout[i*M+:M])
		);
		dpm #(M) u_mcn(
			.in1(cNout[i*M+:M]),
			.in2(dp),
			.out(mcNout[i*M+:M])
		);
		if (i > 1) begin
			dpm #(M) u_mbn(
				.in1(bNout[i*M+:M]),
				.in2(dr),
				.out(mbNout[i*M+:M])
			);
		end
	end

	generate
		/* cN drdcer */
		for (i = 2; i <= T; i = i + 1) begin : drdcer
			always @(posedge clk) begin
				if (synpe)
					cNout[i*M+:M] <= #TCQ 0;
				else if (snce)
					cNout[i*M+:M] <= #TCQ cNin[i*M+:M];
			end
		end

		/* bN drdcer */
		for (i = 4; i <= T; i = i + 1) begin : bN_drdcer
			always @(posedge clk) begin
				if (synpe)
					bNout[i*M+:M] <= #TCQ 0;
				else if (snce)
					bNout[i*M+:M] <= bsel ? cNout[(i-2)*M+:M] : bNout[(i-2)*M+:M];
			end
		end
	endgenerate

endmodule
