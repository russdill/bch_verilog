`include "bch_syndrome.vh"
`include "bch_defs.vh"

function [`BCH_PARAM_SZ-1:0] bch_params;
	input [31:0] data_bits;
	input [31:0] target_t;
	integer m;
	integer min_mt;
	integer min_mb;
	integer done;
	integer done2;
	integer done3;
	integer syn_no;
	integer next_syn_no;
	integer first;
	integer a;
	integer t;
	integer nk;
	integer k;
	integer i;
begin
	min_mt = log2(target_t * 4);
	min_mb = log2(data_bits + 1);
	m = min_mt > min_mb ? min_mt : min_mb;

	done3 = 0;
	while (!done3 && m <= `MAX_M) begin
		done2 = 0;
		syn_no = 1;
		first = lpow(m, 1);
		nk = 0;
		while (!done2) begin
			a = first;
			done = 0;
			while (!done) begin
				a = finite_mult(m, a, a);
				nk = nk + 1;
				if (a == first)
					done = 1;
			end
			next_syn_no = next_syndrome(m, syn_no);
			for (i = 0; i < next_syn_no - syn_no; i = i + 1)
				first = mul1(m, first);
			syn_no = next_syn_no;
			if (2 * target_t - 1 < syn_no) begin
				t = (syn_no - 1) / 2;
				done2 = 1;
			end
		end
		k = m2n(m) - nk;
		if (k >= data_bits)
			done3 = 1;
		else
			m = m + 1;
	end
	if (m == `MAX_M) begin
		m = 0;
		k = 0;
		t = 0;
	end
	bch_params = `BCH_PARAMS(m, k, t, data_bits, syndrome_count(m, t));
end
endfunction
