`timescale 1ns / 1ps

/* serial with inversion */
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
	output reg [M*(T+1)-1:0] cNout = 1
);

	`include "bch.vh"

	localparam TCQ = 1;

	wire [M-1:0] dr;
	wire [M-1:0] dra;
	wire [M-1:0] drpd;
	wire [M-1:0] dli;
	wire [M-1:0] dmIn;
	wire [M-1:0] cs;
	wire [M-1:0] c1in;
	wire [T:2] cin;
	wire [M*(T+1)-1:0] snNen;

	reg [M*(T+1)-1:M*2] bNout = 0;
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

	assign b3ce = caLast && !cbBeg;
	assign b2ce = synpe || b3ce;

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
	assign c1in = {syn1[M-2:0], syn1[M-1]};

	/* snNe dandm */
	assign snNen[0+:M] = c0first ? snNout[0+:M] : 0;
	for (i = 1; i <= T; i = i + 1) begin : sn
		assign snNen[i*M+:M] = cNout[i*M] ? snNout[i*M+:M] : 0;
	end

	generate_cs #(M, T) u_generate_cs(snNen, cs);

	always @(posedge clk) begin
		/* b2 drd1ce */
		if (b2ce)
			bNout[2*M] <= #TCQ bsel;

		/* qdrOr drdr1ce */
		if (synpe || caLast)
			qdr_or <= #TCQ |dra;

		/* qdd drdce */
		if (caLast)
			qd <= #TCQ drpd;

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

		/* c1 dshpe */
		if (synpe)
			cNout[1*M+:M] <= #TCQ c1in;
		else if (cce)
			cNout[1*M+:M] <= #TCQ {cNout[1*M+:M-1], cNout[1*M+M-1]};
	end
	
	serial_standard_multiplier_final #(M) msm_serial_standard_multiplier_final(
		.clk(clk), 
		.run(!caLast),
		.start(msmpe),
		.standard_in(cs),
		.out(dr)
	);

	dinv #(M) inv_dinv(
		.clk(clk),
		.cbBeg(cbBeg),
		.bsel(bsel),
		.caLast(caLast),
		.cce(cce),
		.drnzero(drnzero),
		.snce(snce),
		.synpe(synpe),
		.standard_in(dra),
		.dual_out(drpd)
	);

	if (bch_is_pentanomial(M)) begin
		serial_cannot_handle_pentanomials_yet u_schpy();

	end else begin
		/* Basis rearranging */
		dmli #(M) mli_dmli(
			.in(drpd),
			.out(dli)
		);
		assign dmIn = caLast ? dli : qd;
	end
	generate
		/* cN dshr */
		for (i = 2; i <= T; i = i + 1) begin : c
			always @(posedge clk) begin
				if (cbBeg)
					cNout[i*M+:M] <= #TCQ 0;
				else if (cce)
					cNout[i*M+:M] <= #TCQ {cNout[i*M+:M-1], cNout[i*M+M-1] ^ cin[i]};
			end
		end

		/* ccN drdce */
		for (i = 2; i < T - 1; i = i + 1) begin : cc
			always @(posedge clk) begin
				if (ccCe)
					ccNout[i*M+:M] <= #TCQ cNout[i*M+:M];
			end
		end

		/* mbN */
		serial_mixed_multiplier #(M, T - 1) u_serial_mixed_multiplier(
			.clk(clk),
			.start(dringPe),
			.dual_in(dmIn),
			.standard_in(bNout[2*M+:(T-1)*M]),
			.dual_out(cin[2+:(T-1)])
		);

		/* bN drdce */
		for (i = 5; i <= T; i = i + 1) begin : b
			always @(posedge clk)
				if (caLast)				/* bNin, xbN dmul21 */
					bNout[i*M+:M] <= #TCQ xbsel ? ccNout[(i-2)*M+:M] : bNout[(i-2)*M+:M];
		end
	endgenerate
endmodule
