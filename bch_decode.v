`timescale 1ns / 1ps

module bch_decode #(
	parameter N = 15,
	parameter K = 5,
	parameter T = 3,	/* Correctable errors */
	parameter OPTION = "SERIAL"
) (
	input clk,
	input reset,
	input din,
	output vdout,
	output reg dout = 0
);

`include "bch.vh"

localparam TCQ = 1;
localparam M = $clog2(N+2) - 1;
localparam INTERLEAVE = calc_interleave(N, T);
localparam ITERATION = M + 2;
localparam CHPE = T * ITERATION - 2;
localparam _BUF_SIZE = CHPE / INTERLEAVE + 2;
localparam BUF_SIZE = (_BUF_SIZE > K + 1) ? K : _BUF_SIZE; /* FIXME: possible off by one?, comment indicates BUF_SIZE > K */
/* buf_size= chpe/interleave + 2 if buf_size<k+1; else buf_size= k */

wire [M-1:0] dra;
wire [M-1:0] dr;
wire [M-1:0] drpd;
wire [M-1:0] dli;
wire [M-1:0] dmIn;
wire [M-1:0] cs;
wire [M-1:0] c1in;
wire [M-1:0] dm;
wire [T:2] cin;

reg [M-1:0] qd = 0;
reg [M*(T+1)-1:M] cNout = 0;
reg [M*(T-1)-1:M*2] ccNout = 0;
reg [M*(T+1)-1:M*3] bNout = 0;
reg [K-1:0] bufk = 0;
reg [BUF_SIZE-1:0] buf_ = 0;

wire b2ce;
wire b3ce;
wire b3set;
wire b4set;
wire b3sIn;
wire b4sIn;

wire bsel;
wire synpe;
wire msmpe;
wire chpe;
wire dringPe;
wire caLast;
wire cbBeg;
wire drnzero;
wire cce;
wire snce;
wire xbsel;
wire cei;
wire ccCe;
wire bufCe;
wire bufkCe;
wire vdout1;
wire c0first;
wire err;

reg qdr_or = 0;
reg b2out = 0;

genvar i;
genvar j;

/* b2 drd1ce */
always @(posedge clk)
	if (b2ce)
		b2out <= #TCQ bsel;
assign b3ce = caLast && !cbBeg;
assign b2ce = synpe || b3ce;

assign dra = synpe ? syn1 : dr;

/* qdrOr drdr1ce */
always @(posedge clk)
	if (synpe || caLast)
		qdr_or <= #TCQ |dra;

assign drnzero = synpe ? |dra : qdr_or;

dssbm #(M) msm_dssbm(
	.clk(clk), 
	.run(!caLast),
	.start(msmpe),
	.in(cs),
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
	.in(dra),
	.out(drpd)
);

/* qdd drdce */
always @(posedge clk)
	if (caLast)
		qd <= #TCQ drpd;

assign b3set = synpe || (b3ce && !bsel);
assign b3sIn = synpe && !drnzero;

/* drdcesone b3 */
always @(posedge clk) begin
	if (b3set)
		bNout[3*M+:M] <= #TCQ {{M-1{1'b0}}, b3sIn};
	else if (b3ce)
		bNout[3*M+:M] <= #TCQ cNout[1*M+:M];
end

assign xbsel = bsel || cbBeg;
assign ccCe = (msmpe && cbBeg) || caLast;
assign c1in = {syn1[M-2:0], syn1[M-1]};
/* c1 dshpe */
always @(posedge clk) begin
	if (synpe)
		cNout[1*M+:M] <= #TCQ c1in;
	else if (cce)
		cNout[1*M+:M] <= #TCQ {cNout[1*M+:M-1], cNout[1*M+M-1]};
end
assign cin[2] = dm[0] && b2out && !cbBeg;

if (bch_is_pentanomial(M)) begin
	/* FIXME */

end else begin
	dmli #(M) mli_dmli(
		.in(drpd),
		.out(dli)
	);
	assign dmIn = caLast ? dli : qd;
	dsdbmRing #(M) u_dring(
		.clk(clk),
		.pe(dringPe),
		.dual_in(dmIn),
		.dual_out(dm)
	);
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
	for (i = 3; i <= T; i = i + 1) begin : mb
		dsdbm #(M) u_dsdbm(
			.dual_in(bNout[i*M+:M]),
			.standard_in(dm),
			.out(cin[i])
		);
	end
endgenerate

if (T > 3) begin
	assign b4set = caLast && !bsel;
	assign b4sIn = !cbBeg && b2out;
end

generate
	if (T > 3) begin
		/* b4 drdceSOne */
		always @(posedge clk) begin
			if (b4set)
				bNout[4*M+:M] <= #TCQ {{M-1{1'b0}}, b4sIn};
			else if (caLast)
				bNout[4*M+:M] <= #TCQ ccNout[2*M+:M];
		end
	end

	/* bN drdce */
	for (i = 5; i <= T; i = i + 1) begin : b
		always @(posedge clk)
			if (caLast)				/* bNin, xbN dmul21 */
				bNout[i*M+:M] <= #TCQ xbsel ? ccNout[(i-2)*M+:M] : bNout[(i-2)*M+:M];
	end
endgenerate

/* count dcount */
bch_decode_control #(N, K, T) u_count(
	.clk(clk),
	.reset(reset),
	.drnzero(drnzero),
	.bsel(bsel),
	.bufCe(bufCe),
	.bufkCe(bufkCe),
	.chpe(chpe),
	.msmpe(msmpe),
	.snce(snce),
	.synpe(synpe),
	.vdout(vdout),
	.vdout1(vdout1),
	.c0first(c0first),
	.cce(cce),
	.caLast(caLast),
	.cbBeg(cbBeg),
	.dringPe(dringPe),
	.cei(cei)
);

wire [2*T*M-1:M] synN;

/* sN dsynN */
bch_syndrome #(M, T) u_bch_syndrome(
	.clk(clk),
	.ce(cei),
	.pe(synpe),
	.din(din),
	.out(synN)
);

wire [M*(T+1)-1:0] rearranged;
reg [M*(2*T-1)-1:0] snNout = 0;
wire [M*(T+1)-1:0] snNen;
wire [M*(2*T-1)-1:0] snNin;

wire [M-1:0] syn1 = synN[M*1+:M];


wire [M-1:0] sn0en = snNen[M*0+:M];
wire [M-1:0] sn1en = snNen[M*1+:M];
wire [M-1:0] sn2en = snNen[M*2+:M];
wire [M-1:0] sn3en = snNen[M*3+:M];

wire [M-1:0] syn2 = synN[M*2+:M];
wire [M-1:0] syn3 = synN[M*3+:M];
wire [M-1:0] syn4 = synN[M*4+:M];
wire [M-1:0] syn5 = synN[M*5+:M];

wire [M-1:0] sn0in = snNin[M*0+:M];
wire [M-1:0] sn1in = snNin[M*1+:M];
wire [M-1:0] sn2in = snNin[M*2+:M];
wire [M-1:0] sn3in = snNin[M*3+:M];

wire [M-1:0] sn0out = snNout[M*0+:M];
wire [M-1:0] sn1out = snNout[M*1+:M];
wire [M-1:0] sn2out = snNout[M*2+:M];
wire [M-1:0] sn3out = snNout[M*3+:M];
wire [M-1:0] sn4out = snNout[M*4+:M];

wire [M-1:0] c1out = cNout[1*M+:M];
wire [M-1:0] c2out = cNout[2*M+:M];
wire [M-1:0] c3out = cNout[3*M+:M];

if (OPTION != "SERIAL")
	only_serial_decoder_available u_osda();

/* snNe dandm */
assign snNen[0+:M] = c0first ? snNout[0+:M] : 0;
for (i = 1; i <= T; i = i + 1) begin : sn
	assign snNen[i*M+:M] = cNout[i*M] ? snNout[i*M+:M] : 0;
end

/* xN dmul21 */
for (i = 0; i < 2*T-1; i = i + 1) begin : x
	if (i != T + 1 || T > 3)
		assign snNin[M*i+:M] = synpe ? synN[M*((2*T+1-i)%(2*T-1)+1)+:M] : snNout[M*((i+(2*T-3))%(2*T-1))+:M];
end

/* sN drdce */
generate
	for (i = 0; i < 2*T-1; i = i + 1) begin : s
		if (i == T + 1 && T < 4) begin
			always @(posedge clk)
				if (synpe)
					snNout[i*M+:M] <= #TCQ synN[(3*T-i-1)*M+:M];
		end else begin
			always @(posedge clk)
				if (snce)
					snNout[i*M+:M] <= #TCQ snNin[i*M+:M];
		end
	end
endgenerate

/* snNen dandm/msN doxrt */
for (i = 0; i < M; i = i + 1) begin : snen
	for (j = 0; j <= T; j = j + 1) begin : ms
		assign rearranged[i*(T+1)+j] = snNen[j*M+i];
	end
end

assign cs[0] = ^rearranged[0*(T+1)+:T+1];
for (i = 1; i < M; i = i + 1) begin : cs_arrange
	assign cs[i] = ^rearranged[i*(T+1)+:T+1];
end

chien #(M, T) u_chien(
	.clk(clk),
	.cei(cei),
	.chpe(chpe),
	.cNout(cNout),
	.err(err)
);

/* buf dbuf */
always @(posedge clk) begin
	if (bufCe)
		buf_ <= #TCQ {buf_[BUF_SIZE-2:0], bufk[K-1]};
	if (bufkCe)
		bufk <= #TCQ {bufk[K-2:0], din};
	dout <= #TCQ (buf_[BUF_SIZE-1] ^ err) && vdout1;
end

endmodule
