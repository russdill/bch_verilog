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
	input ch_start,
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

	assign drnzero = |qdpin;
	assign b23set = synpe || (snce && !bsel);
	assign b2s = synpe && drnzero;
	assign b3s = synpe && !drnzero;

	/* xc1 dmul21 */
	assign cNin[1*M+:M] = synpe ? syn1[0+:M] : mcNout[1*M+:M];

	/* csN dxorm */
	assign cNin[2*M+:M*(T-1)] = mbNout[2*M+:M*(T-1)] ^ mcNout[2*M+:M*(T-1)];

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

		/* c1 drdce */
		if (snce)
			cNout[1*M+:M] <= #TCQ cNin[1*M+:M];
		
		/* cN drdcer */
		if (synpe)
			cNout[2*M+:M*(T-1)] <= #TCQ 0;
		else if (snce)
			cNout[2*M+:M*(T-1)] <= #TCQ cNin[2*M+:M*(T-1)];

		/* ch0 drdce */
		if (ch_start)
			chNout[0*M+:M] <= #TCQ cNout[0*M+:M];

		/* b2 drdcesone */
		if (b23set) begin
			bNout[2*M+:M] <= #TCQ {{M-1{1'b0}}, b2s};
			bNout[3*M+:M] <= #TCQ {{M-1{1'b0}}, b3s};
		end else if (snce)
			bNout[2*M+:M*2] <= #TCQ cNout[0*M+:M*2];
	end

	parallel_standard_multiplier #(M, T - 1) u_mbn(
		.standard_in1(dr),
		.standard_in2(bNout),
		.standard_out(mbNout)
	);

	for (i = 0; i <= T; i = i + 1) begin : parallel_mixed_multiplier
		parallel_standard_multiplier #(M, 2) u_mn(
			.standard_in1(cNout[i*M+:M]),
			.standard_in2({snNout[i*M+:M], dp}),
			.standard_out({mNout[i*M+:M], mcNout[i*M+:M]})
		);
	end

	generate
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
