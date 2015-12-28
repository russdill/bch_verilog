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
	reg [(`BCH_ECC_BITS(P)+1)*`BCH_M(P)-1:0] poly;
	reg [`BCH_N(P)-1:0] roots;
begin

		/* Calculate the roots for this finite field */
	roots = 0;
	for (i = 0; i < `BCH_T(P); i = i + 1) begin
		a = 2 * i + 1;
		for (j = 0; j < `BCH_M(P); j = j + 1) begin
			roots[a] = 1;
			a = (2 * a) % `BCH_N(P);
		end
	end

	nk = 0;
	poly = 1;
	a = lpow(`BCH_M(P), 0);
	for (i = 0; i < `BCH_N(P); i = i + 1) begin
		if (roots[i]) begin
			prev = 0;
			poly[(nk+1)*`BCH_M(P)+:`BCH_M(P)] = 1;
			for (j = 0; j <= nk; j = j + 1) begin
				curr = poly[j*`BCH_M(P)+:`BCH_M(P)];
				poly[j*`BCH_M(P)+:`BCH_M(P)] = finite_mult(`BCH_M(P), curr, a) ^ prev;
				prev = curr;
			end
			nk = nk + 1;
		end
		a = `BCH_MUL1(`BCH_M(P), a);
	end

	encoder_poly = 0;
	for (i = 0; i < nk; i = i + 1)
		encoder_poly[i] = poly[i*`BCH_M(P)+:`BCH_M(P)] ? 1 : 0;
end
endfunction
