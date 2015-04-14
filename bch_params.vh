/*
 * BCH Encode/Decoder Modules
 *
 * Copyright 2014 - Russ Dill <russ.dill@asu.edu>
 * Distributed under 2-clause BSD license as contained in COPYING file.
 */
`include "bch.vh"
`include "bch_defs.vh"

function automatic [`BCH_PARAM_SZ-1:0] bch_params;
	input [31:0] data_bits;
	input [31:0] target_t;
	reg [`MAX_M*(1<<(`MAX_M-1))-1:0] tbl;
	integer m;
	integer min_mt;
	integer min_mb;
	integer done;
	integer syn_no;
	integer t;
	integer k;
	integer syn_count;
begin
	min_mt = log2(target_t * 4);
	min_mb = log2(data_bits + 1);
	m = min_mt > min_mb ? min_mt : min_mb;

	done = 0;
	while (!done && m <= `MAX_M) begin
		syn_no = 1;
		syn_count = 0;
		k = `BCH_M2N(m);
		tbl = syndrome_build_table(m, 2 * target_t - 1);
		while (2 * target_t - 1 >= syn_no) begin
			syn_count = syn_count + 1;
			k = k - syndrome_degree(m, syn_no);
			syn_no = syn_no + 1;
			if (tbl[0*`MAX_M+:`MAX_M] == 1)
				syn_no = 2 * target_t + 1;
			else begin
				while (tbl[syn_no*`MAX_M+:`MAX_M] != syn_no)
					syn_no = syn_no + 1;
			end
		end
		t = (syn_no - 1) / 2;
		if (k >= data_bits)
			done = 1;
		else
			m = m + 1;
	end
	if (m > `MAX_M) begin
		m = 0;
		k = 0;
		t = 0;
	end
	bch_params = `BCH_PARAMS(m, k, t, data_bits, syn_count);
end
endfunction
