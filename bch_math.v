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
	output [N_INPUT-1:0] dual_out
);

	`include "bch.vh"

	localparam TCQ = 1;

	reg [M-1:0] lfsr = 0;
	wire [M-1:0] poly = bch_polynomial(M);
	genvar i;

	/* LFSR for generating aux bits */
	always @(posedge clk) begin
		if (start)
			lfsr <= #TCQ dual_in;
		else
			lfsr <= #TCQ {^(lfsr & poly), lfsr[M-1:1]};
	end

	for (i = 0; i < N_INPUT; i = i + 1) begin : mult
		assign dual_out[i] = ^(standard_in[M*i+:M] & lfsr);
	end
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

	wire [M-2:0] aux;
	wire [M-1:0] poly = bch_polynomial(M);
	wire [M*2-2:0] all;
	genvar i;

	assign all = {aux, dual_in};

	/* Generate additional terms via an LFSR */
	for (i = 0; i < M - 1; i = i + 1) begin : aux_assign
		assign aux[i] = ^(all[i+:M] & poly);
	end

	/* Perform matrix multiplication of terms */
	for (i = 0; i < M; i = i + 1) begin : mult
		assign dual_out[i] = ^(all[i+:M] & standard_in);
	end

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
	`include "bch.vh"
	genvar i, j;

	generate
	for (i = 0; i < M; i = i + 1) begin : BLOCKS
		/* alpha^i * standard_in1, each block does one mult */
		wire [M-1:0] bits;

		/* Bit i of each block */
		wire [M-1:0] z;

		/* Stage 1, multiply by alpha once for each block */
		if (i == 0)
			assign bits = standard_in1;
		else
			assign bits = mul1(M, BLOCKS[i-1].bits);

		/* Arrange bits for input into stage 2 */
		for (j = 0; j < M; j = j + 1) begin : arrange
			assign z[j] = BLOCKS[j].bits[i];
		end

		/* Perform multiplication */
		for (j = 0; j < N_INPUT; j = j + 1) begin : mult
			assign standard_out[j*M+i] = ^(standard_in2[j*M+:M] & z);
		end
	end
	endgenerate
endmodule

/*
 * Final portion of MSB first bit-serial standard basis multiplier
 * Input per cycle:
 *	M{a[M-1]} & b
 *	M{a[M-2]} & b
 *	...
 *	M[a[0]} & b
 * The above input stage can be combined with other functions.
 * Takes M cycles
 */
module serial_standard_multiplier_final #(
	parameter M = 4
) (
	input clk,
	input run, /* FIXME: Probably not required */
	input start,
	input [M-1:0] standard_in,
	output reg [M-1:0] out = 0
);
	`include "bch.vh"

	localparam TCQ = 1;
	localparam POLY = bch_polynomial(M);

	always @(posedge clk) begin
		if (start)
			out <= #TCQ standard_in;
		else if (run)
			out <= standard_in ^ {out[M-2:0], 1'b0} ^ (POLY & {M{out[M-1]}});
	end
endmodule

/* Square the standard basis input */
module parallel_standard_square #(
	parameter M = 4
) (
	input [M-1:0] standard_in,
	output [M-1:0] standard_out
);
	`include "bch.vh"

	genvar i, j;
	for (i = 0; i < M; i = i + 1) begin : out_assign
		wire [M-1:0] terms = lpow(M, i * 2);
		wire [M-1:0] rot;
		for (j = 0; j < M; j = j + 1) begin : rotate
			assign rot[j] = out_assign[j].terms[i];
		end
		assign standard_out[i] = ^(standard_in & rot);
	end
endmodule

/*
 * Divider, takes M clock cycles.
 * Inverse of denominator is calculated by using fermat inverter:
 * 	a^(-1) = (a^2)*(a^2^2)*(a^2^3)....*(a^2^(m-1))
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
	input reset,
	input start,
	input [M-1:0] standard_numer,
	input [M-1:0] standard_denom,
	output [M-1:0] dual_out,
	output reg busy = 0
);
	`include "bch.vh"

	localparam TCQ = 1;

	reg busy_last = 0;
	reg [M-1:0] standard_a = 0;
	wire [M-1:0] standard_b;
	reg [M-1:0] dual_c = standard_to_dual(M, lpow(M, 0));
	wire [M-1:0] dual_d;
	wire [log2(M)-1:0] count;

	assign dual_out = dual_d;

	/* Since standard_to_dual doesn't support pentanomials */
	if (bch_is_pentanomial(M))
		inverter_cannot_handle_pentanomials_yet u_ichp();

	/* Square the input each cycle */
	parallel_standard_square #(M) u_dsq(
		.standard_in(start ? standard_denom : standard_a),
		.standard_out(standard_b)
	);

	/* Accumulate the term each cycle (Reuse for C = A*B^(-1) ) */
	parallel_mixed_multiplier #(M) u_parallel_mixed_multiplier(
		.dual_in(dual_c),
		.standard_in((busy || busy_last) ? standard_a : standard_numer),
		.dual_out(dual_d)
	);

	lfsr_counter #(log2(M)) u_counter(
		.clk(clk),
		.reset(start),
		.count(count)
	);

	always @(posedge clk) begin
		busy_last <= #TCQ busy;
		if (start && !reset)
			busy <= #TCQ 1;
		else if (count == lfsr_count(log2(M), M - 2) || reset)
			busy <= #TCQ 0;

		if (start || reset)
			dual_c <= #TCQ standard_to_dual(M, lpow(M, 0));
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
		wire [M-1:0] bits;
		/* first_term = a_i * alpha^(3*i) */
		assign ft_in[i] = in[i];
		assign bits = lpow(M, 3 * i);
	end

	/* i = 0 to m - 2, j = i to m - 1 */
	for (k = 0; k < M * M; k = k + 1) begin : SECOND_TERM
		/* i = k / M, j = j % M */
		wire [M-1:0] bits;
		if (k/M < k%M) begin
			/* second_term = a_i * a_j * (alpha^(2*i+j) + alpha^(2*i+j)) */
			assign st_in[k] = in[k/M] & in[k%M];
			assign bits = lpow(M, 2*(k/M)+k%M) ^ lpow(M, 2*(k%M)+k/M);
		end else begin
			assign st_in[k] = 0;
			assign bits = 0;
		end
	end

	for (i = 0; i < M; i = i + 1) begin : CALC
		wire [M-1:0] first_term;
		wire [M*M-1:0] second_term;

		/* Rearrange bits for multiplication */
		for (j = 0; j < M; j = j + 1) begin : arrange1
			assign first_term[j] = FIRST_TERM[j].bits[i];
		end

		for (j = 0; j < M*M; j = j + 1) begin : arrange2
			assign second_term[j] = SECOND_TERM[j].bits[i];
		end

		/* a^3 = first_term + second_term*/
		assign out[i] = ^(ft_in & first_term) ^ ^(st_in & second_term);
	end
	endgenerate
endmodule

module generate_cs #(
	parameter M = 4,
	parameter T = 3
) (
	input [M*(T+1)-1:0] terms,
	output [M-1:0] cs
);
	wire [M*(T+1)-1:0] rearranged;
	genvar i, j;

	/* cs generation, input rearranged_in, output cs */
	/* snNen dandm/msN doxrt */
	for (i = 0; i < M; i = i + 1) begin : snen
		for (j = 0; j <= T; j = j + 1) begin : ms
			assign rearranged[i*(T+1)+j] = terms[j*M+i];
		end
	end

	/* msN dxort */
	for (i = 0; i < M; i = i + 1) begin : cs_arrange
		assign cs[i] = ^rearranged[i*(T+1)+:T+1];
	end

endmodule

module lfsr_counter #(
	parameter M = 4
) (
	input clk,
	input reset,
	output reg [M-1:0] count = 1
);
	`include "bch.vh"

	localparam TCQ = 1;

	always @(posedge clk)
		count <= #TCQ reset ? 1'b1 : {count[M-2:0], 1'b0} ^
			({M{count[M-1]}} & bch_polynomial(M));
endmodule
