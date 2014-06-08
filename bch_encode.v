`timescale 1ns / 1ps

module bch_encode #(
	parameter M = 4,
	parameter K = 5,	/* Code data bits */
	parameter T = 3,	/* Correctable errors */
	parameter B = K		/* Actual data bits (may be less than K) */
) (
	input clk,
	input start,		/* First cycle */
	input data_in,		/* Input data */
	input accepted,		/* Output cycle accepted */
	output reg data_out = 0,/* Encoded output */
	output reg first = 0,	/* First output cycle */
	output reg last = 0,	/* Last output cycle */
	output busy
);

`include "bch.vh"

/* Calculate least common multiple which has x^2t .. x as its roots */
function [E-1:0] encoder_poly;
	input dummy;
	integer nk;
	integer i;
	integer j;
	integer a;
	integer curr;
	integer prev;
	reg [(E+1)*M-1:0] poly;
	reg [N-1:0] roots;
begin

	/* Calculate the roots for this finite field */
	roots = 0;
	for (i = 0; i < T; i = i + 1) begin
		a = 2 * i + 1;
		for (j = 0; j < M; j = j + 1) begin
			roots[a] = 1;
			a = (2 * a) % N;
		end
	end

	nk = 0;
	poly = 1;
	a = lpow(M, 0);
	for (i = 0; i < N; i = i + 1) begin
		if (roots[i]) begin
			prev = 0;
			poly[(nk+1)*M+:M] = 1;
			for (j = 0; j <= nk; j = j + 1) begin
				curr = poly[j*M+:M];
				poly[j*M+:M] = finite_mult(M, curr, a) ^ prev;
				prev = curr;
			end
			nk = nk + 1;
		end
		a = mul1(M, a);
	end

	for (i = 0; i < nk; i = i + 1)
		encoder_poly[i] = poly[i*M+:M] ? 1 : 0;
end
endfunction

localparam TCQ = 1;
localparam N = m2n(M);
localparam E = N - K; /* ECC bits */
localparam ENC = encoder_poly(0);
localparam SWITCH = lfsr_count(M, B - 2);
localparam DONE = lfsr_count(M, N - 3);

reg [E-1:0] lfsr = 0;
wire [M-1:0] count;
reg load_lfsr = 0;
reg busy_internal = 0;
reg waiting = 0;
reg penult = 0;

/* Input XOR with highest LFSR bit */
wire lfsr_in = load_lfsr && (lfsr[E-1] ^ data_in);

lfsr_counter #(M) u_counter(
	.clk(clk),
	.reset(start && accepted),
	.ce(accepted && busy_internal),
	.count(count)
);

assign busy = busy_internal || (waiting && !accepted);

always @(posedge clk) begin
	if (accepted) begin
		first <= #TCQ start;

		if (start) begin
			penult <= #TCQ 0;
			last <= #TCQ 0;
		end else if (busy_internal) begin
			penult <= #TCQ count == DONE;
			last <= #TCQ penult;
		end

		/*
		 * Keep track of whether or not we are running so we don't send out
		 * spurious last signals as the count wraps around.
		 */
		if (start)
			busy_internal <= #TCQ 1;
		else if (penult && accepted)
			busy_internal <= #TCQ 0;

		if (start)
			load_lfsr <= #TCQ 1'b1;
		else if (count == SWITCH)
			load_lfsr <= #TCQ 1'b0;

		if (start)
			lfsr <= #TCQ {N-K{data_in}} & ENC;
		else if (busy_internal)
			lfsr <= #TCQ {lfsr[E-2:0], 1'b0} ^ ({E{lfsr_in}} & ENC);

		if (busy_internal || start)
			data_out <= #TCQ (load_lfsr || start) ? data_in : lfsr[E-1];
	end

	if (penult && !accepted)
		waiting <= #TCQ 1;
	else if (accepted)
		waiting <= #TCQ 0;
end

endmodule
