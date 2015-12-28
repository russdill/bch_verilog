/*
 * BCH Encode/Decoder Modules
 *
 * Copyright 2014 - Russ Dill <russ.dill@asu.edu>
 * Distributed under 2-clause BSD license as contained in COPYING file.
 */
`include "bch.vh"

/*
 * dat goes from 1..2*t-1, its the output syndromes
 * Each dat is generated from a syn, an lfsr register
 * syn1 (dat1, dat2, dat4), syn3 (dat3), syn5 (dat5)
 * idxes number syns (syn1->0, syn3->1, syn5->2, etc)
 */
function integer idx2syn;
	input [31:0] idx;
	integer i;
	integer s;
begin
	i = 0;
	s = 1;
	while (i < idx) begin
		if (TBL[s*`MAX_M+:`MAX_M] != s)
			i = i + 1;
		s = s + 1;
	end
	idx2syn = s;
end
endfunction

function integer dat2syn;
	input [31:0] dat;
	dat2syn = TBL[dat*`MAX_M+:`MAX_M];
endfunction

function integer dat2idx;
	input [31:0] dat;
	integer syn;
	integer i;
	integer s;
begin
	syn = dat2syn(dat);
	i = 0;
	for (s = 1; s != syn; s = s + 1)
		if (TBL[s*`MAX_M+:`MAX_M] == s)
			 i = i + 1;
	dat2idx = i;
end
endfunction


/* 0 = first method, 1 = second method */
/*
 * If the number of syndromes using the same minimal polynomial is more
 * than one or the degree of the minimal polynomial is less than m, the
 * second method of the calculating syndromes is chosen
 */
function integer syndrome_method;
	input [31:0] t;
	input [31:0] s;
	integer done;
	integer s_degree;
	integer i;
	integer first_way;
begin
	s_degree = syndrome_degree(`BCH_M(P), s);

	/* We must use the first method if syndrome size is full */
	first_way = s_degree == `BCH_M(P);
	done = !first_way;

	for (i = s + 1; !done && i <= 2 * t - 1; i = i + 1) begin
		if (TBL[i*`MAX_M+:`MAX_M] == s) begin
			/* yay, we can use the second method */
			first_way = 0;
			done = 1;
		end
	end

	syndrome_method = !first_way;
end
endfunction

