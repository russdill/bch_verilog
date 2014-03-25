`timescale 1ns / 1ps

module bch_encode #(
	parameter N = 15,	/* Code + Input (Output) */
	parameter K = 5,	/* Input size */
	parameter T = 3		/* Correctable errors */
) (
	input clk,
	input reset,
	input din,
	output vdin,
	output reg dout = 0
);

`include "bch.vh"

function integer encoder_poly;
	input [31:0] m;
	input [31:0] t;
	integer n;
	integer nk1;
	integer nk;
	integer s;
	integer next_s;
	integer i;
	integer b;
	integer k;
	integer c;
	integer done;
	integer curr;
	integer prev;
	reg [31:0] poly [1024];

begin
	poly[0] = 1 << (m - 1);
	for (i = 1; i < 1024; i = i + 1)
		poly[i] = 0;

	n = (1 << m) - 1;
	nk1 = m;
	nk = 0;
	s = 1;
	b = 1 << (m - 2);
	while (2 * t - 1 >= s) begin

		c = b;
		done = 0;
		while (!done) begin
			prev = 0;
			for (i = 0; i < nk1; i = i + 1) begin
				curr = poly[i];
				poly[i] = mul(m, curr, c) ^ prev;
				prev = curr;
			end
			poly[i] = prev;
			nk = nk + 1;
			c = mul(m, c, c);
			if (c == b)
				done = 1;
		end

		next_s = next_syndrome(m, s);
		for (i = 0; i < next_s - s; i = i + 1)
			b = mul1(m, b);
		s = next_s;
		nk1 = nk + m;
	end

	k = n - nk;
	encoder_poly = 0;
	for (i = 0; i < nk; i = i + 1) begin
		if (poly[i])
			encoder_poly = encoder_poly | (1 << i);
	end
end
endfunction

localparam TCQ = 1;
localparam M = $clog2(N + 2) - 1;

reg [N-K-1:0] lfsr = 0;
reg [M-1:0] count = 1;
reg vdin1 = 0;

wire rin = din && !reset;
wire rll = vdin && !reset;

/* Input XOR with highest LFSR bit */
wire rin0 = rll && (lfsr[N-K-1] ^ din);

assign vdin = vdin1 && !reset;

always @(posedge clk) begin
	/* c1 ecount */
	if (count == bch_rev(M, lpow(M, K - 1)))
		vdin1 <= #TCQ 1'b0;
	else if (count == bch_rev(M, lpow(M, N - 1)) || reset)
		vdin1 <= #TCQ 1'b1;

	if (reset)
		count <= #TCQ 1'b1;
	else
		count <= #TCQ {count[M-2:0], 1'b0} ^ 
			({M{count[M-1]}} & bch_polynomial(M));

	/* r1 ering */
	if (reset)
		lfsr <= #TCQ 0;
	else
		lfsr <= #TCQ {lfsr[N-K-2:0], 1'b0} ^ ({N-K{rin0}} & encoder_poly(M, T));
	dout <= #TCQ vdin ? rin : lfsr[N-K-1];
end

endmodule
