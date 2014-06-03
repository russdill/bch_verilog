`timescale 1ns / 1ps

module count_ready #(
	parameter N = 15,
	parameter K = 5,
	parameter T = 3,
	parameter COUNT = 1
) (
	input [$clog2(ITERATION+1)-1:0] ca,
	input [$clog2(N * INTERLEAVE / ITERATION + 2)-1:0] cb,
	output ready
);
	`include "bch.vh"
	localparam M = n2m(N);
	localparam ITERATION = M + 2;
	localparam INTERLEAVE = calc_interleave(N, T);
	localparam C = COUNT % (N * INTERLEAVE);
	assign ready = ca == C % ITERATION && cb == C / ITERATION;
endmodule

/* count dcount */
module bch_decode_control #(
	parameter N = 15,
	parameter K = 5,
	parameter T = 3
) (
	input clk,
	input reset,
	input drnzero,
	output bsel,
	output bufCe,
	output bufkCe,
	output chpe,
	output msmpe,
	output snce,
	output synpe,
	output reg vdout = 0,
	output vdout1,
	output c0first,
	output reg cce = 0,
	output caLast,
	output cbBeg,
	output dringPe,
	output cei
);

`include "bch.vh"

localparam TCQ = 1;
localparam M = n2m(N);
/* FIXME: ITERATION = 3 for option 2, M+2 for option 3 */
localparam ITERATION = M + 2;
localparam INTERLEAVE = calc_interleave(N, T);
localparam CHPE = T * ITERATION - 2;
localparam VDOUT = CHPE + INTERLEAVE + 2 - CHPE % INTERLEAVE;

reg [$clog2(ITERATION+1)-1:0] ca = 0;
reg [$clog2(N * INTERLEAVE / ITERATION + 2)-1:0] cb = 0;
reg [$clog2(T+2)-1:0] l = 0;
reg [(INTERLEAVE > 1 ? $clog2(INTERLEAVE+1) : 1)-1:0] ci = 0;

wire res;
wire clast;
wire vdout1R;
wire vdout1S;
wire bufR;
wire lCe;
wire cceR;
wire cceS;
wire cceSR;
wire bufSR;

reg bufkCe1 = 0;
reg vdout11a = 0;
reg vdout11aDel = 0;
reg noFirstVdout = 0;
reg bufCe1 = 0;

count_ready #(N, K, T, N * INTERLEAVE - 1)		u_clast(ca, cb, clast);
count_ready #(N, K, T, CHPE)				u_chpe(ca, cb, chpe);
count_ready #(N, K, T, VDOUT - 2 + K * INTERLEAVE)	u_vdout1R(ca, cb, vdout1R);
count_ready #(N, K, T, VDOUT - 2)			u_vdout1S(ca, cb, vdout1S);
count_ready #(N, K, T, K * INTERLEAVE - 1)		u_bufR(ca, cb, bufR);

assign res = reset || clast;
assign caLast = ca == ITERATION - 1 || res;
/* FIXME: For option 2, lCe = !ca */
assign lCe = caLast && cb;
assign cceR = ca == M - 1;
assign cceS = caLast || synpe;
assign cceSR = cceS || cceR;
assign cbBeg = !cb;
assign c0first = ca == ITERATION - 2;
if (bch_is_pentanomial(M)) begin
	/* FIXME */
end else
	assign dringPe = caLast || ca == M - polyi(M) - 1;
assign msmpe = ca == 1;
assign bufCe = (bufCe1 || CHPE / INTERLEAVE + 2 < K + 2) && cei;
assign bufSR = vdout1S || bufR;
assign cei = INTERLEAVE > 1  ? !ci : 1'b1;
assign bufkCe = bufkCe1 && cei;
assign vdout1 = vdout11a && cei && noFirstVdout;
assign snce = !ca;
assign synpe = !ca && !cb;
assign bsel = drnzero && (cb >= l || synpe);

always @(posedge clk) begin
	/* a1 dca */
	ca <= #TCQ caLast ? 0 : ca + 1'b1;

	/* b1 dcb */
	if (caLast)
		cb <= #TCQ res ? 0 : (cb + 1'b1);

	/* l1 dcl */
	if (synpe)
		l <= #TCQ {{log2(T+1)-1{1'b0}}, bsel};
	else if (lCe && bsel)
		/* 2 * cb - l + 1 */
		l <= #TCQ ((cb << 1) | 1'b1) - l;

	/* i1 dci */
	ci <= #TCQ (reset || ci == INTERLEAVE - 1) ? 0 : ci + 1'b1;

	/* bufk_Ce drd1ce */
	if (res || bufR)
		bufkCe1 <= #TCQ res;

	/* vDoutD dcd1ce */
	vdout <= #TCQ vdout1;

	/* vdout11P drd1ce */
	if (reset || vdout1R || vdout1S)
		vdout11a <= #TCQ vdout1S && !reset;

	/* vdout1aDelay drd1ce */
	vdout11aDel <= #TCQ vdout11a;

	/* noFirstAfterReset drd1ce */
	noFirstVdout <= #TCQ !reset && ((!vdout11a && vdout11aDel) || noFirstVdout);

	/* cceP drd1ce */
	if (cceSR)
		cce <= #TCQ cceS;

	/* bufCeP drd1ce */
	if (bufSR)
		bufCe1 <= #TCQ vdout1S;
end

endmodule
