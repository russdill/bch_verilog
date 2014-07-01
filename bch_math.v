/*
 * BCH Encode/Decoder Modules
 *
 * Copright 2014 - Russ Dill <russ.dill@asu.edu>
 * Distributed under 2-clause BSD license as contained in COPYING file.
 */
`timescale 1ns / 1ps

/*
 * Bit-serial Berlekamp (mixed dual/standard basis) multiplier)
 * Can multiply one dual basis input by N_INPUTS standard basis
 * inputs in M cycles, producing one bit of each output per
 * cycle
 */
module serial_mixed_multiplier #(
	parameter M = 4,
	parameter N_INPUT = 1
) (
	input clk,
	input start,
	input [M-1:0] dual_in,
	input [M*N_INPUT-1:0] standard_in,
	output [N_INPUT-1:0] standard_out
);
	`include "bch.vh"

	localparam TCQ = 1;
	localparam POLY_I = `BCH_POLYI(M);
	localparam LPOW_P = lpow(M, POLY_I);
	localparam TO = lfsr_count(log2(M), M - POLY_I - 1);
	localparam END = lfsr_count(log2(M), M - 1);

	reg [M-1:0] lfsr = 0;
	reg [M-1:0] dual_stored = 0;
	wire [M-1:0] lfsr_in;
	wire [log2(M)-1:0] count;
	wire change;

	lfsr_counter #(log2(M)) u_counter(
		.clk(clk),
		.reset(start),
		.ce(count != END),
		.count(count)
	);
	assign change = count == TO;

	/* part of basis conversion */
	parallel_mixed_multiplier #(M) u_dmli(
		.dual_in(dual_in),
		.standard_in(LPOW_P[M-1:0]),
		.dual_out(lfsr_in)
	);

	/* LFSR for generating aux bits */
	always @(posedge clk) begin
		if (start)
			dual_stored <= #TCQ dual_in;

		if (start)
			lfsr <= #TCQ lfsr_in;
		else if (change)
			lfsr <= #TCQ dual_stored;
		else if (count != END)
			lfsr <= #TCQ {^(lfsr & `BCH_POLYNOMIAL(M)), lfsr[M-1:1]};
	end

	matrix_vector_multiply #(M, N_INPUT) u_mult(standard_in, lfsr, standard_out);
endmodule

/* Berlekamp bit-parallel dual-basis multiplier */
module parallel_mixed_multiplier #(
	parameter M = 4
) (
	input [M-1:0] dual_in,
	input [M-1:0] standard_in,
	output [M-1:0] dual_out
);
	`include "bch.vh"

	localparam [M-1:0] POLY = `BCH_POLYNOMIAL(M);

	wire [M-2:0] aux;
	wire [M*2-2:0] all;

	assign all = {aux, dual_in};

	/* Generate additional terms via an LFSR */
	compact_matrix_vector_multiply #(M, M-1) u_lfsr(all[M*2-3:0], POLY, aux);

	/* Perform matrix multiplication of terms */
	compact_matrix_vector_multiply #(M) u_mult(all, standard_in, dual_out);
endmodule

/* Bit-parallel standard basis multiplier (PPBML) */
module parallel_standard_multiplier #(
	parameter M = 4,
	parameter N_INPUT = 1
) (
	input [M-1:0] standard_in1,		/* Constant should go here */
	input [M*N_INPUT-1:0] standard_in2,
	output [M*N_INPUT-1:0] standard_out
);
	function [M*M-1:0] gen_matrix;
		input [M-1:0] in;
		integer i;
	begin
		for (i = 0; i < M; i = i + 1)
			gen_matrix[i*M+:M] = i ? `BCH_MUL1(M, gen_matrix[(i-1)*M+:M]) : in;
	end
	endfunction

	matrix_vector_multiplyT #(M) u_mult [N_INPUT-1:0] (gen_matrix(standard_in1), standard_in2, standard_out);
endmodule

/*
 * Final portion of MSB first bit-serial standard basis multiplier (SPBMM)
 * Input per cycle:
 *	M{a[M-1]} & b
 *	M{a[M-2]} & b
 *	...
 *	M[a[0]} & b
 * All products of input pairs are summed together.
 * Takes M cycles
 */
module serial_standard_multiplier #(
	parameter M = 4,
	parameter N_INPUT = 1
) (
	input clk,
	input reset,
	input ce,
	input [M*N_INPUT-1:0] parallel_in,
	input [N_INPUT-1:0] serial_in,
	output reg [M-1:0] out = 0
);
	`include "bch.vh"

	localparam TCQ = 1;

	wire [M*N_INPUT-1:0] z;
	wire [M-1:0] in;
	wire [M-1:0] out_mul1;
	assign out_mul1 = `BCH_MUL1(M, out);

	genvar i;
	for (i = 0; i < N_INPUT; i = i + 1) begin : mult
		assign z[i*M+:M] = {M{serial_in[i]}} & parallel_in[i*M+:M];
	end

	finite_parallel_adder #(M, N_INPUT+1) u_adder({z, out_mul1}, in);

	always @(posedge clk) begin
		if (reset)
			out <= #TCQ 0;
		else if (ce)
			out <= #TCQ in;
	end
endmodule

/* Raise standard basis input to a power */
module parallel_standard_power #(
	parameter M = 4,
	parameter P = 2
) (
	input [M-1:0] standard_in,
	output [M-1:0] standard_out
);
	`include "bch.vh"

	function [M*M-1:0] gen_matrix;
		input dummy;
		integer i;
	begin
		for (i = 0; i < M; i = i + 1)
			gen_matrix[i*M+:M] = lpow(M, i * P);
	end
	endfunction

	matrix_vector_multiplyT #(M) u_mult(gen_matrix(0), standard_in, standard_out);
endmodule

/*
 * Divider, takes M clock cycles.
 * Inverse of denominator is calculated by using fermat inverter:
 * 	a^(-1) = a^(2^n-2) = (a^2)*(a^2^2)*(a^2^3)....*(a^2^(m-1))
 * Wang, Charles C., et al. "VLSI architectures for computing multiplications
 * and inverses in GF (2 m)." Computers, IEEE Transactions on 100.8 (1985):
 * 709-717.
 *
 * Load denominator with start=1. If !busy (M cyles have passed), result is
 * in dual_out. Numerator is not required until busy is low.
 */
module finite_divider #(
	parameter M = 6
) (
	input clk,
	input start,
	input [M-1:0] standard_numer,
	input [M-1:0] standard_denom,
	output [M-1:0] dual_out,
	output reg busy = 0
);
	`include "bch.vh"

	localparam TCQ = 1;
	localparam DONE = lfsr_count(log2(M), M - 2);
	localparam INITIAL = standard_to_dual(M, lpow(M, 0));

	reg [M-1:0] standard_a = 0;
	wire [M-1:0] standard_b;
	reg [M-1:0] dual_c = INITIAL;
	wire [M-1:0] dual_d;
	wire [log2(M)-1:0] count;

	assign dual_out = dual_d;

	/* Since standard_to_dual doesn't support pentanomials */
	if (`BCH_IS_PENTANOMIAL(M))
		inverter_cannot_handle_pentanomials_yet u_ichp();

	/* Square the input each cycle */
	parallel_standard_power #(M, 2) u_dsq(
		.standard_in(start ? standard_denom : standard_a),
		.standard_out(standard_b)
	);

	/*
	 * Accumulate the term each cycle (Reuse for C = A*B^(-1) )
	 * Reuse multiplier to multiply by numerator
	 */
	parallel_mixed_multiplier #(M) u_parallel_mixed_multiplier(
		.dual_in(dual_c),
		.standard_in(busy ? standard_a : standard_numer),
		.dual_out(dual_d)
	);

	lfsr_counter #(log2(M)) u_counter(
		.clk(clk),
		.reset(start),
		.ce(busy),
		.count(count)
	);

	always @(posedge clk) begin
		if (start)
			busy <= #TCQ 1;
		else if (count == DONE)
			busy <= #TCQ 0;

		if (start)
			dual_c <= #TCQ INITIAL;
		else if (busy)
			dual_c <= #TCQ dual_d;

		if (start || busy)
			standard_a <= #TCQ standard_b;
	end
endmodule

/* out = in^3 (standard basis). Saves space vs in^2 * in */
module pow3 #(
	parameter M = 4
) (
	input [M-1:0] in,
	output [M-1:0] out
);
	`include "bch.vh"

	genvar i, j, k;
	wire [M-1:0] ft_in;
	wire [M*M-1:0] st_in;

	generate
	for (i = 0; i < M; i = i + 1) begin : FIRST_TERM
		localparam BITS = lpow(M, 3 * i);
		/* first_term = a_i * alpha^(3*i) */
		assign ft_in[i] = in[i];
	end

	/* i = 0 to m - 2, j = i to m - 1 */
	for (k = 0; k < M * M; k = k + 1) begin : SECOND_TERM
		/* i = k / M, j = j % M */
		/* second_term = a_i * a_j * (alpha^(2*i+j) + alpha^(2*i+j)) */
		localparam BITS = (k/M < k%M) ? (lpow(M, 2*(k/M)+k%M) ^ lpow(M, 2*(k%M)+k/M)) : 0;
		assign st_in[k] = (k/M < k%M) ? (in[k/M] & in[k%M]) : 0;
	end

	for (i = 0; i < M; i = i + 1) begin : CALC
		wire [M-1:0] first_term;
		wire [M*M-1:0] second_term;

		/* Rearrange bits for multiplication */
		for (j = 0; j < M; j = j + 1) begin : arrange1
			assign first_term[j] = FIRST_TERM[j].BITS[i];
		end

		for (j = 0; j < M*M; j = j + 1) begin : arrange2
			assign second_term[j] = SECOND_TERM[j].BITS[i];
		end

		/* a^3 = first_term + second_term*/
		assign out[i] = ^(ft_in & first_term) ^ ^(st_in & second_term);
	end
	endgenerate
endmodule

/*
 * Finite adder, xor each bit
 * Note that for adders with more than 6 inputs, we can utilize the carry
 * chain by passing the output of the carry chain xor through [A-D]MUX and
 * back in [A-D]X and back into the carry chain.
 */
module finite_parallel_adder #(
	parameter M = 4,
	parameter N_INPUT = 2
) (
	input [M*N_INPUT-1:0] in,
	output [M-1:0] out
);
	genvar i, j;

	for (i = 0; i < M; i = i + 1) begin : add
		wire [N_INPUT-1:0] z;
		for (j = 0; j < N_INPUT; j = j + 1) begin : arrange
			assign z[j] = in[j*M+i];
		end
		assign out[i] = ^z;
	end
endmodule

module finite_serial_adder #(
	parameter M = 4
) (
	input clk,
	input start,
	input ce,
	input [M-1:0] parallel_in,
	input serial_in,
	output reg [M-1:0] parallel_out = 0,
	output serial_out
);
	localparam TCQ = 1;

	always @(posedge clk)
		if (start)
			parallel_out <= #TCQ {parallel_in[0+:M-1], parallel_in[M-1]};
		else if (ce)
			parallel_out <= #TCQ {parallel_out[0+:M-1], parallel_out[M-1] ^ serial_in};
	assign serial_out = parallel_out[0];
endmodule

module lfsr_counter #(
	parameter M = 4
) (
	input clk,
	input reset,
	input ce,
	output reg [M-1:0] count = 1
);
	`include "bch.vh"

	localparam TCQ = 1;

	always @(posedge clk)
		if (reset)
			count <= #TCQ 1'b1;
		else if (ce)
			count <= #TCQ `BCH_MUL1(M, count);
endmodule

/* Generate an LFSR term for a series of input bits */
module lfsr_term #(
	parameter M = 15,
	parameter [M-1:0] POLY = 0,
	parameter BITS = 1
) (
	input [BITS-1:0] in,
	output [M-1:0] out
);
	wire [M*BITS-1:0] in_terms;
	genvar j;
	for (j = 0; j < BITS; j = j + 1) begin : lfsr_build
		wire [M-1:0] poly;
		assign poly = j ? `BCH_MUL_POLY(M, lfsr_build[j > 0 ? j-1 : 0].poly, POLY) : POLY;
		assign in_terms[j*M+:M] = in[j] ? poly : 1'b0;
	end

	finite_parallel_adder #(M, BITS) u_adder(
		.in(in_terms),
		.out(out)
	);
endmodule

