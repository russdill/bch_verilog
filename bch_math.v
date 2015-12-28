/*
 * BCH Encode/Decoder Modules
 *
 * Copyright 2014 - Russ Dill <russ.dill@asu.edu>
 * Distributed under 2-clause BSD license as contained in COPYING file.
 */
`timescale 1ns / 1ps
`include "config.vh"

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
	output [N_INPUT-1:0] dual_out
);
	`include "bch.vh"

	localparam TCQ = 1;

	reg [M-1:0] lfsr;

	always @(posedge clk) begin
		if (start)
			lfsr <= #TCQ dual_in;
		else
			lfsr <= #TCQ {^(lfsr & `BCH_POLYNOMIAL(M)), lfsr[M-1:1]};
	end

	matrix_vector_multiply #(M, N_INPUT) u_mult(standard_in, lfsr, dual_out);
endmodule

/*
 * Combine the serial mixed multiplier with a dual basis to standard basis
 * conversion so it can feed the serial polynomial multiplier. The serial
 * mixed multplier outputs a dual basis result LSB first, the serial polynomial
 * multiplier accepts a standard basis input MSB first. An example of a dual
 * to standard basis conversion matrix for a trinomial looks like this:
 *
 * 543210
 * ------
 * 000001 0
 * 100000 1
 * 010000 2
 * 001000 3
 * 000100 4
 * 000010 5
 *
 * So we need the second output of the multiplier first, followed by the 3rd,
 * 4th, 5th, 6th, and then the 1st output. We can preload the multiplier state
 * register so that it outputs the 2nd bit first, and then load it with the
 * original input at the appropriate time. Other trinomials are similar, but
 * start with the 3rd, 4th, or 5th output and thus the preload calculation is
 * slightly more complicated.
 *
 * Pentonomials offer a bit more of a challenge. It's easy to see that the
 * conversion matrix is divided into a lower matrix and an upper matrix. The
 * lower matrix gives an identical start to the trinomial state, but at some
 * point, the original value must be added back in.
 *
 * At some point in time, a switch to the upper matrix is made. The value
 * loaded is the combination of 2 or more values. Similar to the lower matrix,
 * at certain points in time, values must be subtracted out.
 *
 * 109876543210
 * ------------
 * 000000001000  0
 * 000000001100  1
 * 000000000110  2
 * 000000000011  3
 * 100000100000  4
 * 010000010000  5
 * 001000000000  6
 * 000100000000  7
 * 000010000000  8
 * 000001000000  9
 * 000000100000 10
 * 000000010000 11
 */

module serial_mixed_multiplier_dss #(
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

	/* Width/height of upper matrix */
	localparam D = `BCH_DUALD(M);

	/* Dual to standard conversion matrix lower */
	localparam [M-1:0] DSL = dsl_vector(M);

	/* Dual to standard conversion matrix upper */
	localparam [M-1:0] DSU = dsu_vector(M);

	localparam MAX_COUNT = M - 2;
	localparam CB = log2(MAX_COUNT);

	reg [M-1:0] lfsr = 0;
	wire [M-1:0] lfsr_add;

	/* Store original value, and also the upper matrix value for the lfsr */
	reg [M-1:0] dual_stored = 0;

	wire [CB-1:0] count;
	reg change = 0;

	wire [M*(D+1)-1:0] dual_dsu_part;
	wire [M-1:0] dual_dsu;
	wire [M-1:0] dual_dsl;

	lfsr_counter #(CB) u_counter(
		.clk(clk),
		.reset(start),
		.ce(1'b1),
		.count(count)
	);

	/* Handle pentanomials */
	genvar i;
	generate
	if (`CONFIG_CONST_OP) begin
		/* Fast forward initial multiplier state */
		parallel_mixed_multiplier_const_standard #(M, lpow(M, D + 1)) u_dmli1(
			.dual_in(dual_in),
			.dual_out(dual_dsl)
		);
		/* Initial LFSR state for DSU */
		for (i = 1; i < D + 1; i = i + 1) begin : MULT
			if (DSU[i])
				parallel_mixed_multiplier_const_standard #(M, lpow(M, i)) u_dmli3(
					.dual_in(dual_in),
					.dual_out(dual_dsu_part[i*M+:M])
				);
			else
				assign dual_dsu_part[i*M+:M] = 0;
		end
	end else begin
		parallel_mixed_multiplier #(M) u_dmli1(
			.dual_in(dual_in),
			.standard_in(lpow(M, D + 1)),
			.dual_out(dual_dsl)
		);
		for (i = 1; i < D + 1; i = i + 1) begin : MULT
			if (DSU[i])
				parallel_mixed_multiplier #(M) u_dmli3(
					.dual_in(dual_in),
					.standard_in(lpow(M, i)),
					.dual_out(dual_dsu_part[i*M+:M])
				);
			else
				assign dual_dsu_part[i*M+:M] = 0;
		end
	end
	endgenerate

	assign dual_dsu_part[0+:M] = dual_in;
	finite_parallel_adder #(M, D+1) u_adder(dual_dsu_part, dual_dsu);

	/*
	 * Determines when bits are shifting into DSL or out of DSU. This
	 * determines when to add/subtract out mod
	 */
	generate
	if (`BCH_IS_PENTANOMIAL(M)) begin
		/* Modify LFSR */
		reg [M-1:0] mod = 0;
		wire [M-3:0] vector_bits;
		reg vector_bit = 0;

		assign vector_bits[0] = DSL[M - D - 3] && start;
		for (i = 0; i < M - D - 3; i = i + 1) begin : ASSIGN_DSL
			assign vector_bits[i + 1] = DSL[M - D - 4 - i] &&
					!start && count == lfsr_count(CB, i);
		end

		for (i = 0; i < D; i = i + 1) begin : ASSIGN_DSU
			assign vector_bits[i + M - D - 2] = DSU[D - i] &&
					!start &&
					count == lfsr_count(CB, i + M - D - 2);
		end

		assign lfsr_add = {M{vector_bit}} & mod;

		always @(posedge clk) begin
			if (start)
				/* Load the DSL/DSU shift in/out value */
				mod <= #TCQ dual_dsl;

			/* Do a shift out/in of mod next cycle */
			vector_bit <= |vector_bits;
		end
	end else
		assign lfsr_add = 0;
	endgenerate

	always @(posedge clk) begin
		if (start)
			/* Used to load the mod register with a DSU value*/
			dual_stored <= #TCQ dual_dsu;

		if (M - D == 2)
			change <= #TCQ start;
		else
			change <= #TCQ count == lfsr_count(CB, M - D - 3) &&
					!start;

		if (start)
			/* Start with DSL */
			lfsr <= #TCQ dual_dsl;
		else if (change)
			/* Switch to DSU */
			lfsr <= #TCQ dual_stored;
		else
			lfsr <= #TCQ {^(lfsr & `BCH_POLYNOMIAL(M)), lfsr[M-1:1]} ^
				lfsr_add;
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

module parallel_mixed_multiplier_const_dual #(
	parameter M = 4,
	parameter [M-1:0] DUAL_IN = 1
) (
	input [M-1:0] standard_in,
	output [M-1:0] dual_out
);
	`include "bch.vh"

	localparam [M-1:0] POLY = `BCH_POLYNOMIAL(M);

	function [M*2-2:0] gen_matrix;
		input dummy;
		integer i;
	begin
		gen_matrix[0+:M] = DUAL_IN;
		for (i = 0; i < M - 1; i = i + 1)
			gen_matrix[i+M] = ^(gen_matrix[i+:M] & POLY);
	end
	endfunction

	/* Perform matrix multiplication of terms */
	compact_const_matrix_multiply #(.C(M), .MATRIX(gen_matrix(0))) u_mult(standard_in, dual_out);
endmodule

module parallel_mixed_multiplier_const_standard #(
	parameter M = 4,
	parameter [M-1:0] STANDARD_IN = 1
) (
	input [M-1:0] dual_in,
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
	compact_const_vector_multiply #(M, STANDARD_IN) u_mult(all, dual_out);
endmodule

/* Bit-parallel standard basis multiplier (PPBML) */
module parallel_standard_multiplier #(
	parameter M = 4,
	parameter N_INPUT = 1
) (
	input [M-1:0] standard_in1,
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

/* Bit-parallel standard basis multiplier (PPBML) */
module parallel_standard_multiplier_const1 #(
	parameter M = 4,
	parameter [M-1:0] STANDARD_IN1 = 0
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
			gen_matrix[i*M+:M] = i ? `BCH_MUL1(M, gen_matrix[(i-1)*M+:M]) : STANDARD_IN1;
	end
	endfunction

	const_matrix_multiplyT #(.C(M), .MATRIX(gen_matrix(0))) u_mult(standard_in, standard_out);
endmodule

module parallel_standard_multiplier_const2 #(
	parameter M = 4,
	parameter [M-1:0] STANDARD_IN2 = 0
) (
	input [M-1:0] standard_in,
	output [M-1:0] standard_out
);
	function [M*M-1:0] gen_matrix;
		input [M-1:0] in;
		integer i;
	begin
		for (i = 0; i < M; i = i + 1)
			gen_matrix[i*M+:M] = i ? `BCH_MUL1(M, gen_matrix[(i-1)*M+:M]) : in;
	end
	endfunction

	const_vector_multiplyT #(.C(M), .VECTOR(STANDARD_IN2)) u_mult(gen_matrix(standard_in), standard_out);
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

	if (`CONFIG_CONST_OP)
		const_matrix_multiplyT #(.C(M), .MATRIX(gen_matrix(0))) u_mult(standard_in, standard_out);
	else
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
	localparam INITIAL = `BCH_DUAL(M);

	reg [M-1:0] standard_a = 0;
	wire [M-1:0] standard_b;
	reg [M-1:0] dual_c = INITIAL;
	wire [M-1:0] dual_d;
	wire [log2(M)-1:0] count;

	assign dual_out = dual_d;

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

/*
 * Takes input for M clock cycles (MSB concurrent with start).
 * Inverted input is available after an additional M clock cycles.
 * Input is required to be 0 during second set of M clock cycles.
 * Berlekamp-Massy algorithm performing gauss elimination. Documented in
 * VLSI Aspects on Inversion in Finite Fields, Mikael Olofsson 2002.
 */
module berlekamp_inverter #(
	parameter M = 4
) (
	input clk,
	input start,

	input standard_in,
	output [M-1:0] standard_out
);
	localparam TCQ = 1;

	reg [M-1:0] A = 0;
	reg [M-2:0] B = 0;
	reg [M-2:0] C = 0;
	reg [$clog2(M+1)-1:0] r = 0;
	reg [$clog2(M+1)-1:0] s = 0;
	reg rs_next = 0; /* Set if r < s for next cycle */
	reg ff = 0;
	wire delta;
	wire Tr;

	assign Tr = ff ^ standard_in;
	/* Note: delta is very wide, 2M + 2 */
	assign delta = ^(B & C) ^ Tr;
	assign standard_out = A;

	always @(posedge clk) begin
		if (start) begin
			r <= #TCQ !standard_in;
			s <= #TCQ standard_in;
			rs_next <= #TCQ standard_in;
			ff <= #TCQ 0;
			A <= #TCQ (standard_in << (M - 1));
			B <= #TCQ 0;
			C <= #TCQ (standard_in << (M - 2));
		end else begin
			if (!delta || rs_next) begin
				A <= #TCQ A >> 1;
				r <= #TCQ r + 1'b1;
				rs_next <= #TCQ r + 1 < s;
			end else begin
				A <= #TCQ {1'b1, B};
				s <= #TCQ r + 1'b1;
				r <= #TCQ s;
				rs_next <= s < r + 1;
			end
			ff <= #TCQ ^(C & `BCH_POLYNOMIAL(M));
			B <= #TCQ B ^ ({M-1{delta}} & (A >> 1));
			C <= #TCQ (Tr << (M - 2)) | (C >> 1);
		end

	end
endmodule

/*
 * Inverter, takes M clock cycles.
 * Inverse of denominator is calculated by using fermat inverter:
 * 	a^(-1) = a^(2^n-2) = (a^2)*(a^2^2)*(a^2^3)....*(a^2^(m-1))
 * Wang, Charles C., et al. "VLSI architectures for computing multiplications
 * and inverses in GF (2 m)." Computers, IEEE Transactions on 100.8 (1985):
 * 709-717.
 */
module fermat_inverter #(
	parameter M = 6
) (
	input clk,
	input start,
	input [M-1:0] standard_in,
	output [M-1:0] dual_out
);
	`include "bch.vh"

	localparam TCQ = 1;
	localparam INITIAL = `BCH_DUAL(M);

	reg [M-1:0] standard_a = 0;
	wire [M-1:0] standard_b;
	reg [M-1:0] dual_c = INITIAL;
	wire [M-1:0] dual_d;

	assign dual_out = dual_c;

	/* Square the input each cycle */
	parallel_standard_power #(M, 2) u_dsq(
		.standard_in(start ? standard_in : standard_a),
		.standard_out(standard_b)
	);

	/* Accumulate the term each cycle */
	parallel_mixed_multiplier #(M) u_parallel_mixed_multiplier(
		.dual_in(dual_c),
		.standard_in(standard_a),
		.dual_out(dual_d)
	);

	always @(posedge clk) begin
		dual_c <= #TCQ start ? INITIAL : dual_d;
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
	output reg [M-1:0] count = lfsr_count(M, 0)
);
	`include "bch.vh"

	localparam TCQ = 1;

	always @(posedge clk)
		if (reset)
			count <= #TCQ lfsr_count(M, 0);
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

