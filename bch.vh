/*
 * m = power of field
 * l = irreducable polynomial for m
 * n = code word size (1 << m) - 1
 * k = input size
 * t = correctable bits
 */

`include "log2.vh"
`include "bch_defs.vh"

/* Berlekamp dual-basis multiplier for fixed values, returns value in dual basis */
function [`MAX_M-1:0] fixed_mixed_multiplier;
	input [31:0] m;
	input [`MAX_M-1:0] dual_in;
	input [`MAX_M-1:0] standard_in;
	integer i;
	integer poly;
	integer aux;
	integer ret;
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

function integer conversion_term;
	input [31:0] m;
	input [31:0] bit_pos;
	integer pos;
begin
	pos = `BCH_POLYI(m);
	if (`BCH_IS_PENTANOMIAL(m)) begin
		/* FIXME: Support pentanomials */
	end else begin
		conversion_term = 1 << ((pos - bit_pos - 1) % m);
	end
end
endfunction

/* Convert polynomial basis to dual basis */
function integer standard_to_dual;
	input [31:0] m;
	input [31:0] standard;
	integer i;
	integer ret;
begin
	ret = 0;
	for (i = 0; i < m; i = i + 1) begin
		if (standard[i])
			ret = ret ^ conversion_term(m, i);
	end
	standard_to_dual = ret;
end
endfunction

/* a * b for finite field */
function integer finite_mult;
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
function integer lpow;
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

function integer lfsr_count;
	input [31:0] m;
	input [31:0] n;
begin
	lfsr_count = lpow(m, n);
end
endfunction

