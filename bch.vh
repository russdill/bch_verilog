/*
 * m = power of field
 * l = irreducable polynomial for m
 * n = code word size (1 << m) - 1
 * k = input size
 * t = correctable bits
 */

localparam MAX_M = 16;

/* Trinomial */
function [MAX_M:0] P3;
	input [31:0] p;
	P3 = (1 << p) | 1;
endfunction

/* Pentanomial */
function [MAX_M:0] P5;
	input [31:0] p1;
	input [31:0] p2;
	input [31:0] p3;
	P5 = (1 << p3) | (1 << p2) | (1 << p1) | 1;
endfunction

/* Return irreducable polynomial */
/* VLSI Aspects on Inversion in Finite Fields, Mikael Olofsson */
function integer bch_polynomial;
	input [31:0] m;
	reg [(MAX_M+1)*(MAX_M-1)-1:0] p;
begin
	p = {
		P3(1),		/* m=2 */
		P3(1),
		P3(1),
		P3(2),		/* m=5 */
		P3(1),
		P3(1),
		P5(4, 3, 2),
		P3(4),
		P3(3),		/* m=10 */
		P3(2),
		P5(6, 4, 1),
		P5(4, 3, 1),
		P5(5, 3, 1),
		P3(1),		/* m=15 */
		P5(12, 3, 1)
	};
	bch_polynomial = p[(MAX_M+1)*(MAX_M-m)+:MAX_M+1];
end
endfunction

/*
 * Non-zero if irreducible polynomial is of the form x^m + x^P1 + x^P2 + x^P3 + 1
 * zero for x^m + x^P + 1
 */
function integer bch_is_pentanomial;
	input [31:0] m;
	integer i;
	integer degree;
	integer p;
begin
	p = bch_polynomial(m);
	degree = 1;
	while (p) begin
		if (p & 1)
			degree = degree + 1;
		p = p >> 1;
	end
	bch_is_pentanomial = degree == 5 ? 1 : 0;
end
endfunction

function integer polyi;
	input [31:0] m;
	polyi = $clog2((bch_polynomial(m) >> 1) + 1);
endfunction

function integer conversion_term;
	input [31:0] m;
	input [31:0] bit_pos;
	integer pos;
begin
	pos = polyi(m);
	if (bch_is_pentanomial(m)) begin
		/* FIXME */
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
begin
	standard_to_dual = 0;
	for (i = 0; i < m; i = i + 1) begin
		if (standard & (1 << i))
			standard_to_dual = standard_to_dual ^ conversion_term(m, i);
	end
end
endfunction

function integer bch_rev;
	input [31:0] m;
	input [31:0] in;
	integer i;
begin
	bch_rev = 0;
	for (i = 0; i < m; i = i + 1)
		bch_rev = (bch_rev << 1) | in[i];
end
endfunction

/* Multiply by alpha x*l^1 */
function integer mul1;
	input [31:0] m;
	input [MAX_M:0] x;
	integer l;
begin
	l = bch_rev(m, bch_polynomial(m));
	mul1 = x >> 1;
	if (x & 1)
		mul1 = mul1 ^ l;
end
endfunction

/* a * b */
function integer mul;
	input [31:0] m;
	input [MAX_M:0] a;
	input [MAX_M:0] b;
	integer i;

begin
	mul = 0;
	if (a && b) begin
		for (i = 0; i < m; i = i + 1) begin
			mul = mul1(m, mul);
			if (b & (1 << i))
				mul = mul ^ a;
		end
	end
end
endfunction

/* x^n */
function integer pow;
	input [31:0] m;
	input [MAX_M:0] x;
	input [31:0] p;
	integer i;

begin
	pow = x;
	repeat (p - 1)
		pow = mul(m, pow, x);
end
endfunction

/* L^x */
function integer lpow;
	input [31:0] m;
	input [31:0] x;
	integer i;

begin
	lpow = 1 << (m - 1);
	x = x % ((1 << m) - 1); 
	repeat (x)
		lpow = mul1(m, lpow);
end
endfunction

function integer next_syndrome;
	input [31:0] m;
	input [31:0] s;
	integer n;
	integer tmp;
	integer done;

begin
	n = (1 << m) - 1;
	next_syndrome = s + 2;
	tmp = next_syndrome;
	done = 0;

	while (!done) begin
		tmp = (tmp * 2) % n;
		if (tmp < next_syndrome) begin
			next_syndrome = next_syndrome + 2;
			tmp = next_syndrome;
		end else if (tmp == next_syndrome)
			done = 1;
	end
end
endfunction

function integer calc_interleave;
	input [31:0] n;
	input [31:0] t;
	integer chpe;
	integer vdout;
	integer done;
	integer m;
	integer iteration;
begin
	m = $clog2(n+2) - 1;
	iteration = m + 2;
	calc_interleave = 1;
	done = 0;
	while (!done) begin
		chpe = t * iteration - 2;
		vdout = chpe + calc_interleave + 2 - chpe % calc_interleave;
		if (vdout - 2 < n * calc_interleave)
			done = 1;
		else
			calc_interleave = calc_interleave + 1;
	end
end
endfunction

