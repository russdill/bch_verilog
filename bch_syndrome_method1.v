`timescale 1ns / 1ps

/*
 * Calculate syndrome method 1:
 *
 * S_j = r_0 + alpha^j * (r_1 + alpha^j * ...(r_(n-2) + alpha^j * r_(n-1))...)
 *
 * 0: z = n - 1, accumulator = 0
 * 1: accumulator += r_z
 * 2: accumulator *= alpha^j
 * 3: z = z - 1
 * 4: z >= 0 -> goto 1
 */
module dsynN_method1 #(
	parameter M = 4,
	parameter T = 3,
	parameter IDX = 0
) (
	input clk,
	input ce,			/* Accept additional bit */
	input start,			/* Accept first bit of syndrome */
	input data_in,
	output reg [M-1:0] synN = 0
);
	`include "bch.vh"

	function integer first_way_terms;
		input [31:0] m;
		input [31:0] s;
		input [31:0] bit_pos;
		integer i;
	begin
		for (i = 0; i < m; i = i + 1)
			first_way_terms[i] = (lpow(m, i + s) >> bit_pos) & 1;
	end
	endfunction

	localparam TCQ = 1;
	localparam SYN = idx2syn(M, IDX);

	genvar bit_pos;

	for (bit_pos = 0; bit_pos < M; bit_pos = bit_pos + 1) begin : first
		always @(posedge clk) begin
			if (start)
				synN[bit_pos] <= #TCQ bit_pos ? 1'b0 : data_in;
			else if (ce)
				synN[bit_pos] <= #TCQ
					^(synN & first_way_terms(M, SYN, bit_pos)) ^
					(bit_pos ? 0 : data_in);
		end
	end
endmodule

module syndrome_expand_method1 #(
	parameter M = 4
) (
	input [M-1:0] in,
	output [M-1:0] out
);
	assign out = in;
endmodule
