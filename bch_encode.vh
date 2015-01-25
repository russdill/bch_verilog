/*
 * BCH Encode/Decoder Modules
 *
 * Copyright 2014 - Russ Dill <russ.dill@asu.edu>
 * Distributed under 2-clause BSD license as contained in COPYING file.
 */
 
/* Calculate least common multiple which has x^2t .. x as its roots */
function [`BCH_ECC_BITS(P)-1:0] encoder_poly;
	input dummy;
	integer nk;
	integer i;
	integer j;
	integer a;
	integer curr;
	integer prev;
	reg [(`BCH_ECC_BITS(P)+1)*M-1:0] poly;
	reg [`BCH_N(P)-1:0] roots;
begin

		/* Calculate the roots for this finite field */
	roots = 0;
	for (i = 0; i < `BCH_T(P); i = i + 1) begin
		a = 2 * i + 1;
		for (j = 0; j < M; j = j + 1) begin
			roots[a] = 1;
			a = (2 * a) % `BCH_N(P);
		end
	end

	nk = 0;
	poly = 1;
	a = lpow(M, 0);
	for (i = 0; i < `BCH_N(P); i = i + 1) begin
		if (roots[i]) begin
			prev = 0;
			poly[(nk+1)*M+:M] = 1;
			for (j = 0; j <= nk; j = j + 1) begin
				curr = poly[j*M+:M];
				poly[j*M+:M] = finite_mult(M, curr, a) ^ prev;
				prev = curr;
			end
			nk = nk + 1;
		end
		a = `BCH_MUL1(M, a);
	end

	encoder_poly = 0;
	for (i = 0; i < nk; i = i + 1)
		encoder_poly[i] = poly[i*M+:M] ? 1 : 0;
end
endfunction
