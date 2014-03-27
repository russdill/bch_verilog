`timescale 1ns / 1ps

module dch #(
	parameter M = 4,
	parameter P = 1
) (
	input clk,
	input ce,
	input pe,
	input [M-1:0] in,
	output reg [M-1:0] out = 0
);
	`include "bch.vh"

	localparam TCQ = 1;

	function integer chien_terms;
		input [31:0] m;
		input [31:0] bit_pos;
		input [31:0] no;
		integer i;
	begin
		chien_terms = 0;
		for (i = 0; i < m; i = i + 1)
			chien_terms = chien_terms | (((lpow(M, i + no) >> (m - 1 - bit_pos)) & 1) << i);
	end
	endfunction

	integer i;

	always @(posedge clk) begin
		if (pe)
			out <= #TCQ in;
		else if (ce) begin
			for (i = 0; i < M; i = i + 1)
				out[i] <= #TCQ ^(out & chien_terms(M, i, P));
		end
	end
endmodule

module chien #(
	parameter M = 4,
	parameter T = 3
) (
	input clk,
	input cei,
	input chpe,
	input [M*(T+1)-1:M] cNout,
	output err
);
	wire [M-1:0] eq;
	wire [M*(T+1)-1:M] chout;
	wire [M*T-1:0] chien_mask;
	
	genvar i;
	generate
		/* Chien search */
		/* chN dchN */
		for (i = 1; i <= T; i = i + 1) begin : ch
			dch #(M, i) u_ch(clk, cei, chpe, cNout[i*M+:M], chout[i*M+:M]);
		end
	endgenerate

	/* cheg dcheq */
	for (i = 0; i < M*T; i = i + 1) begin : CHEG
		assign chien_mask[i] = !(i % M);
	end

	for (i = 0; i < M; i = i + 1)
		assign eq[i] = ^(chout[M*(T+1)-1:M] & (chien_mask << i));
	assign err = !(eq ^ 1'b1);
endmodule
