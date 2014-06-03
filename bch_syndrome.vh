`include "bch.vh"

function integer first_way_terms;
	input [31:0] m;
	input [31:0] s;
	input [31:0] bit_pos;

	integer i;
begin
	for (i = 0; i < m; i = i + 1)
		first_way_terms[i] = (lpow(m, i + s) >> bit_pos) & 1;
end
endfunction

function integer second_way_terms;
	input [31:0] m;
	input [31:0] s;
	input [31:0] bit_pos;
	integer i;
begin
	for (i = 0; i < m; i = i + 1)
		second_way_terms[i] = (lpow(m, i * s) >> bit_pos) & 1;
end
endfunction

function integer syndrome_size;
	input [31:0] m;
	input [31:0] s;
	integer b;
	integer c;
	integer done;
	integer ret;
begin
	ret = 0;
	b = lpow(m, s);
	c = b;
	done = 0;

	while (!done) begin
		ret = ret + 1;
		c = finite_mult(m, c, c);
		if (c == b)
			done = 1;
	end
	syndrome_size = ret;
end
endfunction

/* 0 = first method, 1 = second method */
function integer syndrome_method;
	input [31:0] m;
	input [31:0] t;
	input [31:0] s;
	integer done;
	integer s_size;
	integer i;
	integer first_way;
begin
	done = 0;
	s_size = syndrome_size(m, s);

	done = 0;
	i = s;
	first_way = 1;
	while (!done) begin
		if (i <= 2 * t - 1) begin
			if (i != s)
				first_way = 0;
		end
		i = (i * 2) % m2n(m);
		if (i == s)
			done = 1;
	end
	first_way = first_way && s_size == m;
	syndrome_method = !first_way;
end
endfunction

function [(1<<MAX_M)-1:0] syndrome_poly;
	input [31:0] m;
	input [31:0] s;
	integer i;
	integer b;
	integer c;
	integer done;
	integer curr;
	integer prev;
	integer s_size;
	reg [(1<<MAX_M)*MAX_M-1:0] poly;
begin
	poly[0*(1<<MAX_M)+:1<<MAX_M] = 1;
	for (i = 1; i < MAX_M; i = i + 1)
		poly[i*(1<<MAX_M)+:1<<MAX_M] = 0;

	b = lpow(m, s);
	c = b;
	done = 0;
	s_size = 0;

	while (!done) begin
		prev = 0;
		for (i = 0; i < MAX_M; i = i + 1) begin
			curr = poly[i*(1<<MAX_M)+:1<<MAX_M];
			poly[i*(1<<MAX_M)+:1<<MAX_M] = finite_mult(m, curr, c) ^ prev;
			prev = curr;
		end
		poly[i*(1<<MAX_M)+:1<<MAX_M] = prev;

		s_size = s_size + 1;

		c = finite_mult(m, c, c);
		if (c == b)
			done = 1;
	end

	for (i = 0; i < s_size; i = i + 1)
		syndrome_poly[i] = poly[i*(1<<MAX_M)+:1<<MAX_M] ? 1 : 0;
end
endfunction

function integer syndrome_count;
	input [31:0] m;
	input [31:0] t;
	integer s;
	integer ret;
begin
	s = 1;
	ret = 0;
	while (s <= 2 * t - 1) begin
		ret = ret + 1;
		s = next_syndrome(m, s);
	end
	syndrome_count = ret;
end
endfunction

/*
 * dat goes from 1..2*t-1, its the output syndromes
 * Each dat is generated from a syn, an lfsr register
 * syn1 (dat1, dat2, dat4), syn3 (dat3), syn5 (dat5)
 * idxes number syns (syn1->0, syn3->1, syn5->2, etc)
 */
function integer syn2idx;
	input [31:0] m;
	input [31:0] syn;
	integer s;
	integer ret;
begin
	s = 1;
	ret = 0;
	while (s != syn) begin
		ret = ret + 1;
		s = next_syndrome(m, s);
	end
	syn2idx = ret;
end
endfunction

function integer idx2syn;
	input [31:0] m;
	input [31:0] idx;
	integer i;
	integer ret;
begin
	ret = 1;
	i = 0;
	while (i != idx) begin
		i = i + 1;
		ret = next_syndrome(m, ret);
	end
	idx2syn = ret;
end
endfunction

function integer dat2syn;
	input [31:0] m;
	input [31:0] dat;
	integer s;
	integer i;
	integer done;
	integer ret;
begin
	s = 1;
	ret = 0;

	while (!ret) begin
		done = 0;
		i = s;
		while (!done && !ret) begin
			if (i == dat)
				ret = s;
			i = (i * 2) % m2n(m);
			if (i == s)
				done = 1;
		end
		if (i == dat)
			ret = s;
		s = next_syndrome(m, s);
	end
	dat2syn = ret;
end
endfunction

function integer dat2idx;
	input [31:0] m;
	input [31:0] dat;
	integer s;
	integer i;
	integer done1;
	integer done2;
	integer ret;
begin
	s = 1;
	ret = 0;
	done1 = 0;
	while (!done1) begin
		done2 = 0;
		i = s;
		while (!done1 && !done2) begin
			if (i == dat)
				done1 = 1;
			i = (i * 2) % m2n(m);
			if (i == s)
				done2 = 1;
		end
		s = next_syndrome(m, s);
		if (!done1)
			ret = ret + 1;
	end
	dat2idx = ret;
end
endfunction
