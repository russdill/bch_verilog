/*
 * BCH Encode/Decoder Modules
 *
 * Copright 2014 - Russ Dill <russ.dill@asu.edu>
 * Distributed under 2-clause BSD license as contained in COPYING file.
 */
`timescale 1ns / 1ps

module compact_matrix_vector_multiply #(
	parameter C = 4,
	parameter R = C
) (
	input [C+R-2:0] matrix,
	input [C-1:0] vector,
	output [R-1:0] out
);
	`include "matrix.vh"
	matrix_vector_multiply #(C, R) u_mult(expand_matrix(matrix), vector, out);
endmodule

module matrix_vector_multiplyT #(
	parameter C = 4,
	parameter R = C
) (
	input [R*C-1:0] matrix,
	input [R-1:0] vector,
	output [C-1:0] out
);
	`include "matrix.vh"
	matrix_vector_multiply #(R, C) u_mult(rotate_matrix(matrix), vector, out);
endmodule

module matrix_vector_multiply #(
	parameter C = 4,
	parameter R = C
) (
	input [C*R-1:0] matrix,
	input [C-1:0] vector,
	output [R-1:0] out
);
	genvar i;
	for (i = 0; i < R; i = i + 1) begin : mult
		assign out[i] = ^(matrix[i*C+:C] & vector);
	end
endmodule

