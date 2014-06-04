`timescale 1ns / 1ps

/* Chien search, determines roots of a polynomial defined over a finite field */

module dch #(
	parameter M = 4,
	parameter P = 1
) (
	input clk,
	input err,		/* Error was found so correct it */
	input errcheck,		/* Try to see if an error was found */
	input ce,
	input start,
	input [M-1:0] in,
	output [M-1:0] out
);
	`include "bch.vh"

	localparam TCQ = 1;
	localparam LPOW = lpow(M, P);

	wire [M-1:0] mul_out;
	reg [M-1:0] _out = 0;

	parallel_standard_multiplier #(M) u_mult(
		.standard_in1(LPOW[M-1:0]),
		.standard_in2(_out ^ err),
		.standard_out(mul_out)
	);

	always @(posedge clk)
		if (start)
			_out <= #TCQ in;
		else if (ce)
			_out <= #TCQ mul_out;

	assign out = _out ^ errcheck;
endmodule

module chien #(
	parameter M = 4,
	parameter T = 3
) (
	input clk,
	input cei,
	input ch_start,
	input [M*(T+1)-1:0] cNout,
	output err
);
	wire [M-1:0] eq;
	wire [M*(T+1)-1:0] chNout;
	wire [M*(T+1)-1:0] chien_mask;
	
	genvar i, j;
	generate
	/* Chien search */
	/* chN dchN */
	for (i = 0; i <= T; i = i + 1) begin : ch
		dch #(M, i) u_ch(
			.clk(clk),
			.err(1'b0),
			.errcheck(1'b0),
			.ce(cei),
			.start(ch_start),
			.in(cNout[i*M+:M]),
			.out(chNout[i*M+:M])
		);
	end
	endgenerate

	finite_adder #(M, T+1) u_dcheq(chNout, eq);

	assign err = !eq;
endmodule
