function integer first_way_terms;
	input [31:0] m;
	input [31:0] s;
	input [31:0] bit_pos;

	integer i;
begin
	first_way_terms = 0;
	for (i = 0; i < m; i = i + 1)
		first_way_terms = first_way_terms | (((lpow(m, i + s) >> (m - 1 - bit_pos)) & 1) << i);
end
endfunction

function integer second_way_terms;
	input [31:0] m;
	input [31:0] s;
	input [31:0] bit_pos;
	integer i;
begin
	second_way_terms = 0;
	for (i = 0; i < m; i = i + 1)
		second_way_terms = second_way_terms | (((lpow(m, i * s) >> (m - 1 - bit_pos)) & 1) << i);
end
endfunction

function integer syndrome_size;
	input [31:0] m;
	input [31:0] s;
	integer b;
	integer c;
	integer done;
begin
	syndrome_size = 0;
	b = lpow(m, s);
	c = b;
	done = 0;

	while (!done) begin
		syndrome_size = syndrome_size + 1;
		c = mul(m, c, c);
		if (c == b)
			done = 1;
	end
end
endfunction

function integer syndrome_method;
	input [31:0] m;
	input [31:0] s;
	integer done;
	integer s_size;
	integer i;
	integer n;
begin
	done = 0;
	n = (1 << m) - 1;
	s_size = syndrome_size(m, s);

	syndrome_method = s_size == m ? 0 : 1;
	done = 0;
	i = s;
	while (!done) begin
		if (i <= s_size) begin
			if (i != s)
				syndrome_method = 1;
		end
		i = (i * 2) % n;
		if (i == s)
			done = 1;
	end
end
endfunction

function integer syndrome_poly;
	input [31:0] m;
	input [31:0] s;
	integer i;
	integer b;
	integer c;
	integer done;
	integer curr;
	integer prev;
	integer s_size;
	reg [31:0] poly [16];
begin
	poly[0] = 1 << (m - 1);
	for (i = 1; i < 16; i = i + 1)
		poly[i] = 0;

	b = lpow(m, s);
	c = b;
	done = 0;
	s_size = 0;

	while (!done) begin
		prev = 0;
		for (i = 0; i < 15; i = i + 1) begin
			curr = poly[i];
			poly[i] = mul(m, curr, c) ^ prev;
			prev = curr;
		end
		poly[i] = prev;

		s_size = s_size + 1;

		c = mul(m, c, c);
		if (c == b)
			done = 1;
	end

	syndrome_poly = 0;
	for (i = 0; i < s_size; i = i + 1) begin
		if (poly[i])
			syndrome_poly = syndrome_poly | (1 << i);
	end
end
endfunction

function integer syndrome_count;
	input [31:0] m;
	input [31:0] t;
	integer s;

begin
	s = 1;
	syndrome_count = 0;
	while (s <= 2 * t - 1) begin
		syndrome_count = syndrome_count + 1;
		s = next_syndrome(m, s);
	end
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
begin
	s = 1;
	syn2idx = 0;
	while (s != syn) begin
		syn2idx = syn2idx + 1;
		s = next_syndrome(m, s);
	end
end
endfunction

function integer idx2syn;
	input [31:0] m;
	input [31:0] idx;
	integer i;
begin
	idx2syn = 1;
	i = 0;
	while (i != idx) begin
		i = i + 1;
		idx2syn = next_syndrome(m, idx2syn);
	end
end
endfunction

function integer dat2syn;
	input [31:0] m;
	input [31:0] dat;
	integer s;
	integer i;
	integer n;
	integer done;
begin
	s = 1;
	dat2syn = 0;

	n = (1 << m) - 1;
	while (!dat2syn) begin
		done = 0;
		i = s;
		while (!done && !dat2syn) begin
			if (i == dat)
				dat2syn = s;
			i = (i * 2) % n;
			if (i == s)
				done = 1;
		end
		if (i == dat)
			dat2syn = s;
		s = next_syndrome(m, s);
	end

end
endfunction

function integer dat2idx;
	input [31:0] m;
	input [31:0] dat;
	integer s;
	integer i;
	integer n;
	integer done1;
	integer done2;
begin
	s = 1;
	dat2idx = 0;
	done1 = 0;
	n = (1 << m) - 1;
	while (!done1) begin
		done2 = 0;
		i = s;
		while (!done1 && !done2) begin
			if (i == dat)
				done1 = 1;
			i = (i * 2) % n;
			if (i == s)
				done2 = 1;
		end
		s = next_syndrome(m, s);
		if (!done1)
			dat2idx = dat2idx + 1;
	end
end
endfunction
