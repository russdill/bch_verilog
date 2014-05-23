`timescale 1ns / 1ps

/* Bit-serial Berlekamp (dual basis) multiplier */
module dsdbm #(
	parameter M = 4
) (
	input [M-1:0] dual_in,
	input [M-1:0] standard_in,
	output out
);
	assign out = ^(standard_in & dual_in);
endmodule

/* Bit-serial Berlekamp dual-basis multiplier LFSR */
module dsdbmRing #(
	parameter M = 4
) (
	input clk,
	input pe,
	input [M-1:0] dual_in,
	output reg [M-1:0] dual_out = 0
);
	`include "bch.vh"

	localparam TCQ = 1;

	always @(posedge clk) begin
		if (pe)
			dual_out <= #TCQ dual_in;
		else
			dual_out <= #TCQ {^(dual_out & bch_polynomial(M)), dual_out[M-1:1]};
	end
endmodule

/* Bit-parallel dual-basis multiplier */
module dpdbm #(
	parameter M = 4
) (
	input [M-1:0] dual_in,
	input [M-1:0] standard_in,
	output [M-1:0] out
);
	`include "bch.vh"

	wire [M-2:0] aux;
	wire [M-1:0] aux_mask = (bch_polynomial(M) & {{M-1{1'b1}}, 1'b0});
	wire [M*2-2:0] all;
	genvar i;

	assign all = {aux, dual_in};

	for (i = 0; i < M - 1; i = i + 1) begin : aux_assign
		assign aux[i] = dual_in[i] ^ ^({aux, dual_in} & (aux_mask << i));
	end

	generate
		for (i = 0; i < M; i = i + 1) begin : MN
			dsdbm #(M) u_dsdbm(all[i+:M], standard_in, out[i]);
		end
	endgenerate
endmodule

/* Bit-parallel standard basis multiplier */
module dpm #(
	parameter M = 4
) (
	input [M-1:0] in1,
	input [M-1:0] in2,
	output [M-1:0] out
);
	`include "bch.vh"

	localparam TCQ = 1;
	localparam Z = (ham(M) - 1) * (M - 1) + 1;
	localparam lZ = log2(Z);

	function [M*M*lZ-1:0] dpm_table;
		input [31:0] m;
		integer i;
		integer j;
		integer poly;
		integer pos;
		integer bi;
	begin
		poly = bch_polynomial(m);

		for (i = 0; i < M; i = i + 1)
			dpm_table[(0*M+i)*lZ+:lZ] = i;

		bi = M;
		for (i = 1; i < M; i = i + 1) begin : convert
			dpm_table[(i*M+0)*lZ+:lZ] = dpm_table[((i-1)*M+M-1)*lZ+:lZ];
			for (j = 1; j < M; j = j + 1) begin
				if ((1 << j) & poly) begin
					dpm_table[(i*M+j)*lZ+:lZ] = bi;
					bi = bi + 1;
				end else
					dpm_table[(i*M+j)*lZ+:lZ] = dpm_table[((i-1)*M+j-1)*lZ+:lZ];
			end
		end
	end
	endfunction

	wire [Z-1:0] b;
	wire [M*M-1:0] cN;
	localparam [M*M*lZ-1:0] map = dpm_table(M);

	genvar i, j;

	assign b[M-1:0] = in1;

	for (i = 0; i < M; i = i + 1) begin : cn_block
		assign cN[i*M] = b[i];
	end

	for (i = 1; i < M; i = i + 1) begin : convert
		assign cN[i] = b[map[(i*M+0)*lZ+:lZ]];
		for (j = 1; j < M; j = j + 1) begin : b_swizzle
			if ((1 << j) & bch_polynomial(M))
				assign b[map[(i*M+j)*lZ+:lZ]] = b[map[((i-1)*M+j-1)*lZ+:lZ]] ^ b[map[((i-1)*M+M-1)*lZ+:lZ]];
			assign cN[j*M+i] = b[map[(i*M+j)*lZ+:lZ]];
		end
		dsdbm #(M) u_mn(
			.dual_in(in2),
			.standard_in(cN[i*M+:M]),
			.out(out[i])
		);
	end

	dsdbm #(M) u_mn(
		.dual_in(in2),
		.standard_in(cN[0+:M]),
		.out(out[0])
	);
endmodule

/* Bit-serial standard basis multiplier */
module dssbm #(
	parameter M = 4
) (
	input clk,
	input run,
	input start,
	input [M-1:0] in,
	output reg [M-1:0] out = 0
);
	`include "bch.vh"

	localparam TCQ = 1;

	always @(posedge clk) begin
		if (start)
			out <= #TCQ in;
		else if (run)
			out <= in ^ {out[M-2:0], 1'b0} ^ (bch_polynomial(M) & {M{out[M-1]}});
	end
endmodule

module dmli #(
	parameter M = 4
) (
	input [M-1:0] in,
	output [M-1:0] out
);
	`include "bch.vh"

	/*
	 * Only for trinomials, multiply by L^P, where P in the middle
	 * exponent, in x^5 + x^2 + 1, P == 2.
	 */
	function integer mli_terms;
		input [31:0] m;
		input [31:0] bit_pos;
		integer i;
		integer j;
		integer poly;
		integer pos;
		integer b;
		integer ret;
	begin
		ret = 0;
		poly = bch_rev(m, bch_polynomial(m));
		pos = polyi(m);
		for (i = 0; i < m; i = i + 1) begin
			b = 1 << (m - 1 - i);
			for (j = 0; j < pos; j = j + 1)
				b = (b << 1) | ((b & poly) ? 1'b1 : 1'b0);
			ret = ret | (((b >> (m - 1 - bit_pos)) & 1) << i);
		end
		mli_terms = ret;
	end
	endfunction

	genvar i;
	for (i = 0; i < M; i = i + 1) begin : out_assign
		assign out[i] = ^(in & mli_terms(M, i));
	end
endmodule

module dsq #(
	parameter M = 4
) (
	input [M-1:0] in,
	output [M-1:0] out
);
	`include "bch.vh"

	function integer sq_terms;
		input [31:0] m;
		input [31:0] bit_pos;
		integer i;
		integer ret;
	begin
		ret = 0;
		for (i = 0; i < m; i = i + 1)
			ret = ret | (((lpow(m, i * 2) >> (m - 1 - bit_pos)) & 1) << i);
		sq_terms = ret;
	end
	endfunction

	genvar i;
	for (i = 0; i < M; i = i + 1) begin : out_assign
		assign out[i] = ^(in & sq_terms(M, i));
	end
endmodule

/* Finite field inversion */
module dinv #(
	parameter M = 4
) (
	input clk,
	input cbBeg,
	input bsel,
	input caLast,
	input cce,
	input drnzero,
	input snce,
	input synpe,
	input [M-1:0] in,
	output [M-1:0] out
);
	`include "bch.vh"

	localparam TCQ = 1;

	wire [M-1:0] msin;
	reg [M-1:0] mdin = standard_to_dual(M, 1);
	wire [M-1:0] sq;
	reg [M-1:0] qsq = 0;

	wire ce1;
	wire ce2;
	wire reset;
	wire ce2a = drnzero && cbBeg;
	wire ce2b = bsel || ce2a;
	wire sel = caLast || synpe;

	if (bch_is_pentanomial(M))
		inverter_cannot_handle_pentanomials_yet u_ichp();

	assign ce1 = ce2 || caLast || synpe;
	assign ce2 = cce && !snce && (bsel || (drnzero && cbBeg));
	assign reset = (snce && bsel) || synpe;

	assign msin = (caLast || synpe) ? in : qsq;
	dsq #(M) u_dsq(msin, sq);
	dpdbm #(M) u_dpdbm(
		.dual_in(mdin),
		.standard_in(msin),
		.out(out)
	);

	always @(posedge clk) begin
		if (ce1)
			qsq <= #TCQ sq;

		if (reset)
			mdin <= #TCQ standard_to_dual(M, 1);
		else if (ce2)
			mdin <= #TCQ out;
	end
endmodule

module pow3 #(
	parameter M = 4
) (
	input [M-1:0] in,
	output [M-1:0] out
);
	`include "bch.vh"

	function [MAX_M*(MAX_M+1)/2-1:0] pow3_terms;
		input [31:0] m;
		input [31:0] bit_pos;
		integer i;
		integer j;
		integer k;
		integer s;
		integer mask;
		integer ret;
	begin
		s = (m * (m + 1)) / 2;
		mask = 1 << (m - 1 - bit_pos);
		k = 1;

		ret = 0;
		for (i = 0; i < m; i = i + 1) begin
			ret = ret | ((lpow(m, 3*i) & mask) ? k : 1'b0);
			k = k << 1;
		end

		for (i = 0; i < m - 1; i = i + 1) begin
			for (j = i + 1; j < m; j = j + 1) begin
				ret = ret | (((lpow(m, 2*i+j) ^ lpow(m, 2*j+i)) & mask) ? k : 1'b0);
				k = k << 1;
			end
		end

		pow3_terms = ret;
	end
	endfunction

	function integer dxor_terms;
		input [31:0] m;
		input [31:0] bit_pos;
		integer k;
		integer i;
		integer done;
		integer ret;
	begin
		k = 0;
		ret = 0;
		done = 0;
		for (i = 0; i < m && !done; i = i + 1) begin
			if (bit_pos < k + m - i) begin
				if (i > 0)
					ret = ret | (1 << (i - 1));
				ret = ret | (1 << (bit_pos - k + i));
				done = 1;
			end
			k = k + m - i;
		end
		dxor_terms = ret;
	end
	endfunction

	wire [M*(M+1)/2-1:0] dxor;
	genvar i;

	for (i = 0; i < M * (M + 1) / 2; i = i + 1) begin : gen_xor
		assign dxor[i] = !(dxor_terms(M, i) & ~in);
	end

	for (i = 0; i < M; i = i + 1) begin : gen_out
		assign out[i] = ^(dxor & pow3_terms(M, i));
	end
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
	assign cs[0] = ^rearranged[0*(T+1)+:T+1];
	for (i = 1; i < M; i = i + 1) begin : cs_arrange
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
