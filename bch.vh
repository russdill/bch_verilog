/*
 * BCH Encode/Decoder Modules
 *
 * Copyright 2014 - Russ Dill <russ.dill@asu.edu>
 * Distributed under 2-clause BSD license as contained in COPYING file.
 */
`include "log2.vh"
`include "bch_defs.vh"

/* Berlekamp dual-basis multiplier for fixed values, returns value in dual basis */
function [`MAX_M-1:0] fixed_mixed_multiplier;
	input [31:0] m;
	input [`MAX_M-1:0] dual_in;
	input [`MAX_M-1:0] standard_in;
	reg [`MAX_M*2-2:0] aux;
	reg [`MAX_M-1:0] ret;
	integer i;
	integer poly;
begin
	poly = `BCH_POLYNOMIAL(m);

	aux = dual_in;
	for (i = 0; i < m - 1; i = i + 1)
		aux[i+m] = ^((aux >> i) & poly);

	ret = 0;
	for (i = 0; i < m; i = i + 1)
		ret[i] = ^((aux >> i) & standard_in);

	fixed_mixed_multiplier = ret;
end
endfunction

/*
 * sd_vector can generate the standard to dual basis conversion matrix by
 * shifting one bit down for each row. Generated square matrix will contain two
 * square matrixies, an upper and lower matrix.
 */
function [`MAX_M*2-2:0] sd_vector;
	input [31:0] m;
	reg [`MAX_M*2-2:0] aux;
	integer i;
	integer poly;
begin
	poly = `BCH_POLYNOMIAL(m);

	aux = `BCH_DUAL(m);
	for (i = 0; i < m - 1; i = i + 1)
		aux[i+m] = ^((aux >> i) & poly);
	sd_vector = aux;
end
endfunction

/*
 * dsu_vector can generate the upper matrix of the dual to standard basis
 * conversion matrix by shifting down one bit for each row. It is created
 * by inverting the upper standard to dual basis matrix, which is simple to
 * do given the symmetry of the matrix
 */
function [`MAX_M-1:0] dsu_vector;
	input [31:0] m;
	reg [`MAX_M-1:0] aux;
	reg [`MAX_M-1:0] sdu_vector;
	integer i;
	integer b;
begin
	b = `BCH_DUALD(m);

	sdu_vector = sd_vector(m);

	aux = 1 << b;
	for (i = 0; i < b; i = i + 1) begin
		aux = aux >> 1;
		aux = aux | ((^(aux & sdu_vector)) << b);
	end
	dsu_vector = aux;
end
endfunction

/*
 * dsl_vector can generate the lower matrix of the dual to standard basis
 * conversion matrix as by shifting up one bit for ecah row. It is created
 * by inverting the lower standard to dual basis matrix.
 */
function [`MAX_M-1:0] dsl_vector;
	input [31:0] m;
	reg [`MAX_M-1:0] sdl_vector;
	reg [`MAX_M-1:0] aux;
	integer i;
	integer b;
begin
	b = `BCH_DUALD(m);

	sdl_vector = sd_vector(m) >> (m + b);

	aux = 1;
	for (i = 0; i < m - (b + 2); i = i + 1) begin
		aux = aux << 1;
		aux = aux | ^(aux & sdl_vector);
	end
	dsl_vector = aux;
end
endfunction

/*
 * Convert dual basis to standard basis by multiplying by the dual to standard
 * upper and lower matricies.
 */
function [`MAX_M-1:0] dual_to_standard;
	input [31:0] m;
	input [`MAX_M-1:0] dual_in;
	reg [`MAX_M-1:0] dsl;
	reg [`MAX_M-1:0] dsu;
	reg [`MAX_M-1:0] mask;
	integer i;
	integer b;
begin
	b = `BCH_DUALD(m);

	dsu = dsu_vector(m) << b;
	dsl = dsl_vector(m) << (b + 1);

	mask = (1 << (b + 1)) - 1;
	for (i = 0; i < b + 1; i = i + 1)
		dual_to_standard[i] = ^((dsu >> i) & mask & dual_in);

	for (i = b + 1; i < m; i = i + 1)
		dual_to_standard[i] = ^((dsl >> i) & (dual_in >> (b + 1)));
end
endfunction


function [`MAX_M-1:0] standard_to_dual;
	input [31:0] m;
	input [`MAX_M-1:0] standard_in;
begin
	/* Just multiply value by dual basis 1 */
	standard_to_dual = fixed_mixed_multiplier(m, `BCH_DUAL(m), standard_in);
end
endfunction

/* a * b for finite field */
function [`MAX_M-1:0] finite_mult;
	input [31:0] m;
	input [`MAX_M:0] a;
	input [`MAX_M:0] b;
	integer i;
	integer p;
begin
	p = 0;
	if (a && b) begin
		for (i = 0; i < m; i = i + 1) begin
			p = p ^ (a & {`MAX_M{b[i]}});
			a = `BCH_MUL1(m, a);
		end
	end
	finite_mult = p;
end
endfunction

/* L^x, convert an integer to standard polynomial basis */
function [`MAX_M-1:0] lpow;
	input [31:0] m;
	input [31:0] x;
	integer i;
	integer ret;
begin
	ret = 1;
	x = x % `BCH_M2N(m);	/* Answer would wrap around */
	repeat (x)
		ret = `BCH_MUL1(m, ret);
	lpow = ret;
end
endfunction

function [`MAX_M-1:0] lfsr_count;
	input [31:0] m;
	input [31:0] n;
begin
	lfsr_count = lpow(m, n);
end
endfunction

function [`MAX_M-1:0] brute_inverse;
	input [31:0] m;
	input [`MAX_M-1:0] in;
	reg [`MAX_M-1:0] t;
begin
	t = lpow(m, 0);
	repeat (`BCH_M2N(m)) begin
		if (finite_mult(m, in, t) == lpow(m, 0))
			brute_inverse = t;
		t = `BCH_MUL1(m, t);
	end
end
endfunction

function [`MAX_M*(1<<(`MAX_M-1))-1:0] syndrome_build_table;
	input [31:0] m;
	input [31:0] t;
	reg [`MAX_M*(1<<(`MAX_M-1))-1:0] tbl;
	integer curr;
	integer s;
	integer next;
	integer n;
	integer count;
begin
	tbl = 0;
	curr = 1;
	s = curr;
	n = `BCH_M2N(m);
	count = 0;

	while (curr <= 2 * t - 1) begin
		next = 0;
		if (s <= 2 * t - 1) begin
			if (tbl[s*`MAX_M+:`MAX_M])
				next = 1;
			else begin
				if (s == curr)
					count = count + 1;
				tbl[s*`MAX_M+:`MAX_M] = curr;
			end
		end
		s = s + s;
		if (s >= n)
			s = s - n;
		if (s == curr || next) begin
			curr = curr + 1;
			s = curr;
		end
	end
	tbl[0+:`MAX_M] = count;
	syndrome_build_table = tbl;
end
endfunction

function integer syndrome_degree;
	input [31:0] m;
	input [31:0] s;
	integer c;
	integer done;
	integer ret;
	integer n;
begin
	ret = 0;
	c = s;
	done = 0;
	n = `BCH_M2N(m);

	while (!done) begin
		ret = ret + 1;
		c = c + c;
		if (c >= n)
			c = c - n;
		if (c == s)
			done = 1;
	end
	syndrome_degree = ret;
end
endfunction

