/*
 * m = power of field
 * l = irreducable polynomial for m
 * n = code word size (1 << m) - 1
 * k = input size
 * t = correctable bits
 */

`include "log2.vh"
`include "bch_defs.vh"

/*
 * Non-zero if irreducible polynomial is of the form x^m + x^P1 + x^P2 + x^P3 + 1
 * zero for x^m + x^P + 1
 */
function integer bch_is_pentanomial;
	input [31:0] m;
	integer p;
	integer bits;
	integer i;
begin
	p = `BCH_POLYNOMIAL(m);
	bits = 1;
	for (i = 0; i < m; i = i + 1) begin
		if (p & 1)
			bits = bits + 1;
		p = p >> 1;
	end
	bch_is_pentanomial = bits == 5 ? 1 : 0;
end
endfunction

/* Degree (except highest), eg, m=5, (1)00101, x^5 + x^2 + 1 returns 2 */
function integer polyi;
	input [31:0] m;
	polyi = log2(`BCH_POLYNOMIAL(m) >> 1);
endfunction

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
	pos = polyi(m);
	if (bch_is_pentanomial(m)) begin
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

/* Multiply by alpha x*l^1 */
function [`MAX_M-1:0] mul1;
	input [31:0] m;
	input [`MAX_M-1:0] x;
begin
	mul1 = m2n(m) & ((x << 1) ^ (`BCH_POLYNOMIAL(m) & {`MAX_M{x[m-1]}}));
end
endfunction

/* a * b for finite field */
function integer finite_mult;
	input [31:0] m;
	input [`MAX_M:0] a;
	input [`MAX_M:0] b;
	integer i;
	integer p;
	reg [`MAX_M-1:0] poly;
	reg [`MAX_M-1:0] mask;
begin
	p = 0;
	poly = `BCH_POLYNOMIAL(m);
	mask = m2n(m);
	if (a && b) begin
		for (i = 0; i < m; i = i + 1) begin
			p = p ^ (a & {`MAX_M{b[i]}});
			a = mask & ((a << 1) ^ (poly & {`MAX_M{a[m-1]}}));	/* mul1(m, a) */
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
	x = x % m2n(m);	/* Answer would wrap around */
	repeat (x)
		ret = mul1(m, ret);
	lpow = ret;
end
endfunction

function integer n2m;
	input [31:0] n;
begin
	n2m = log2(n+1) - 1;
end
endfunction

function integer m2n;
	input [31:0] m;
begin
	m2n = (1 << m) - 1;
end
endfunction

function integer lfsr_count;
	input [31:0] m;
	input [31:0] n;
begin
	lfsr_count = lpow(m, n);
end
endfunction

