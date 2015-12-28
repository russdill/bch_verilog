/*
 * BCH Encode/Decoder Modules
 *
 * Copyright 2014 - Russ Dill <russ.dill@asu.edu>
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

module compact_const_vector_multiply #(
	parameter C = 4,
	parameter [C-1:0] VECTOR = 0,
	parameter R = C
) (
	input [C+R-2:0] matrix,
	output [R-1:0] out
);
	`include "matrix.vh"
	const_vector_multiply #(R, VECTOR, C) u_mult(expand_matrix(matrix), out);
endmodule

module compact_const_matrix_multiply #(
	parameter C = 4,
	parameter R = C,
	parameter [C+R-2:0] MATRIX = 0
) (
	input [C-1:0] vector,
	output [R-1:0] out
);
	`include "matrix.vh"
	const_matrix_multiply #(.C(R), .MATRIX(expand_matrix(MATRIX)), .R(C)) u_mult(vector, out);
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

/* Reducing terms shouldn't be necessary, but it helps under ISE */
/*
 * Each column of the matrix is XOR'd to produce an output.
 * Only row indexes with a non-zero vector index are used.
 */
module const_matrix_multiplyT #(
	parameter C = 4,
	parameter R = C,
	parameter [R*C-1:0] MATRIX = 0
) (
	input [C-1:0] vector,
	output [R-1:0] out
);
	`include "matrix.vh"
	const_matrix_multiply #(.C(R), .MATRIX(rotate_matrix(MATRIX)), .R(C)) u_mult(vector, out);
endmodule

/*
 * Each row of the matrix is XOR'd to produce an output.
 * Only columns indexes with a non-zero vector index are used.
 */
module const_matrix_multiply #(
	parameter C = 4,
	parameter R = C,
	parameter [C*R-1:0] MATRIX = 0
) (
	input [R-1:0] vector,
	output [C-1:0] out
);
	parameter LOG2C = $clog2(C+1);

	function integer degree;
		input [LOG2C-1:0] row;
		integer i;
		integer c;
	begin
		c = 0;
		for (i = 0; i < C; i = i + 1)
			c = c + MATRIX[row*C+i];
		degree = c;
	end
	endfunction

	function [LOG2C*C-1:0] idx;
		input [LOG2C-1:0] row;
		input [LOG2C-1:0] max;
		integer i;
		integer c;
	begin
		c = 0;
		for (i = 0; i < C; i = i + 1) begin
			idx[LOG2C*i+:LOG2C] = c;
			if (MATRIX[row*C+i] && c < max)
				c = c + 1;
		end
	end
	endfunction

	genvar i, j;
	for (i = 0; i < R; i = i + 1) begin : OUT
		localparam DEGREE = degree(i);
		if (DEGREE > 0) begin
			localparam [LOG2C*C-1:0] IDXS = idx(i, DEGREE - 1);

			wire [DEGREE-1:0] terms;

			for (j = 0; j < C; j = j + 1) begin : TERMS
				localparam IDX = IDXS[LOG2C*j+:LOG2C];
				if (MATRIX[i*C+j])
					assign terms[IDX] = vector[j];
			end
			assign out[i] = ^terms;
		end else
			assign out[i] = 0;
	end
endmodule

/*
 * Each column of the matrix is XOR'd to produce an output.
 * Only row indexes with a non-zero vector index are used.
 */
module const_vector_multiplyT #(
	parameter C = 4,
	parameter R = C,
	parameter [R-1:0] VECTOR = 0
) (
	input [C*R-1:0] matrix,
	output [C-1:0] out
);
	`include "matrix.vh"
	const_vector_multiply #(R, VECTOR, C) u_mult(rotate_matrix(matrix), out);
endmodule

/*
 * Each row of the matrix is XOR'd to produce an output.
 * Only columns indexes with a non-zero vector index are used.
 */
module const_vector_multiply #(
	parameter C = 4,
	parameter [C-1:0] VECTOR = 0,
	parameter R = C
) (
	input [C*R-1:0] matrix,
	output [R-1:0] out
);
	parameter LOG2C = $clog2(C+1);

	function integer degree;
		input dummy;
		integer i;
		integer c;
	begin
		c = 0;
		for (i = 0; i < C; i = i + 1)
			c = c + VECTOR[i];
		degree = c;
	end
	endfunction

	function [LOG2C*C-1:0] idx;
		input [LOG2C-1:0] max;
		integer i;
		integer c;
	begin
		c = 0;
		for (i = 0; i < C; i = i + 1) begin
			idx[LOG2C*i+:LOG2C] = c;
			if (VECTOR[i] && c < max)
				c = c + 1;
		end
	end
	endfunction

	localparam DEGREE = degree(0);
	localparam [LOG2C*C-1:0] IDXS = idx(DEGREE - 1);

	if (DEGREE) begin
		genvar i, j;
		for (i = 0; i < R; i = i + 1) begin : ROWS
			wire [DEGREE-1:0] terms;
			for (j = 0; j < C; j = j + 1) begin : TERMS
				localparam IDX = IDXS[LOG2C*j+:LOG2C];
				if (VECTOR[j])
					assign terms[IDX] = matrix[i*C+j];
			end
			assign out[i] = ^terms;
		end
	end else
		assign out = 0;
endmodule
