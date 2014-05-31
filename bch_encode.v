`timescale 1ns / 1ps

module bch_encode #(
	parameter N = 15,	/* Code + Input (Output) */
	parameter K = 5,	/* Input size */
	parameter T = 3		/* Correctable errors */
) (
	input clk,
	input reset,		/* Reset LFSR */
	input data_in,		/* Input data */
	output vdin,		/* Accepting input data */
	output reg data_out = 0	/* Encoded output */
);

`include "bch.vh"

function [(1<<MAX_M)-1:0] encoder_poly;
	input [31:0] m;
	input [31:0] t;
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
	integer ret;
	reg [(1<<MAX_M)*1024-1:0] poly; /* FIXME: 1024 Not big enough for M=16 */

begin
	poly[0*(1<<MAX_M)+:1<<MAX_M] = 1;
	for (i = 1; i < 1024; i = i + 1)
		poly[i*(1<<MAX_M)+:1<<MAX_M] = 0;

	nk1 = m;
	nk = 0;
	s = 1;
	b = 2;
	while (2 * t - 1 >= s) begin

		c = b;
		done = 0;
		while (!done) begin
			prev = 0;
			for (i = 0; i < nk1; i = i + 1) begin
				curr = poly[i*(1<<MAX_M)+:1<<MAX_M];
				poly[i*(1<<MAX_M)+:1<<MAX_M] = finite_mult(m, curr, c) ^ prev;
				prev = curr;
			end
			poly[i*(1<<MAX_M)+:1<<MAX_M] = prev;
			nk = nk + 1;
			c = finite_mult(m, c, c);
			if (c == b)
				done = 1;
		end

		next_s = next_syndrome(m, s);
		for (i = 0; i < next_s - s; i = i + 1)
			b = mul1(m, b);
		s = next_s;
		nk1 = nk + m;
	end

	k = m2n(m) - nk;
	ret = 0;
	for (i = 0; i < nk; i = i + 1) begin
		if (|poly[i*(1<<MAX_M)+:1<<MAX_M])
			ret = ret | (1 << i);
	end
	encoder_poly = ret;

end
endfunction

localparam TCQ = 1;
localparam M = n2m(N);

reg [N-K-1:0] lfsr = 0;
wire [M-1:0] count;
reg vdin1 = 0;

/* Input XOR with highest LFSR bit */
wire lfsr_in = vdin1 && (lfsr[N-K-1] ^ data_in);

assign vdin = vdin1 && !reset;

lfsr_counter #(M) u_counter(
	.clk(clk),
	.reset(reset),
	.count(count)
);

always @(posedge clk) begin
	/* c1 ecount */
	if (count == lfsr_count(M, N - 1) || reset)
		vdin1 <= #TCQ 1'b1;
	else if (count == lfsr_count(M, K - 1))
		vdin1 <= #TCQ 1'b0;

	/* r1 ering */
	if (reset)
		lfsr <= #TCQ 0;
	else
		lfsr <= #TCQ {lfsr[N-K-2:0], 1'b0} ^ ({N-K{lfsr_in}} & encoder_poly(M, T));

	data_out <= #TCQ vdin ? data_in : lfsr[N-K-1];
end

endmodule
