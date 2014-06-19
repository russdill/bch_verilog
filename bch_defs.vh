`ifndef _BCH_DEFS_VH_
`define _BCH_DEFS_VH_

`define MAX_M			16
`define BCH_PARAM_MASK		((1 << `MAX_M) - 1)
`define BCH_PARAM(P, IDX)	(((P) >> (`MAX_M*IDX)) & `BCH_PARAM_MASK)
`define BCH_PARAM_SZ		(`MAX_M*6)

`define BCH_M(P)		`BCH_PARAM(P, 0)
`define BCH_N(P)		`BCH_PARAM(P, 1)
`define BCH_K(P)		`BCH_PARAM(P, 2)
`define BCH_T(P)		`BCH_PARAM(P, 3)
`define BCH_M2N(M)		((1 << M) - 1)
`define BCH_DATA_BITS(P)	`BCH_PARAM(P, 4)
`define BCH_SYNDROMES_SZ(P)	`BCH_PARAM(P, 5)
`define BCH_ECC_BITS(P)		(`BCH_N(P) - `BCH_K(P))
`define BCH_CODE_BITS(P)	(`BCH_ECC_BITS(P) + `BCH_DATA_BITS(P))
`define BCH_SIGMA_SZ(P)		((`BCH_T(P)+1)*`BCH_M(P))
`define BCH_ERR_SZ(P)		log2(`BCH_T(P)+1)

`define BCH_PARAMS(M, K, T, B, SC)	((M) | (`BCH_M2N(M) << `MAX_M) | ((K) << (`MAX_M*2)) | ((T) << (`MAX_M*3)) | ((B) << (`MAX_M*4)) | (((SC)*(M)) << (`MAX_M*5)))
`define BCH_SANE		`BCH_PARAMS(4, 7, 2, 7, 2)

/* Trinomial */
`define BCH_P3(P)		{{`MAX_M{1'b0}} | (1'b1 << P) | 1'b1}

/* Pentanomial */
`define BCH_P5(P1, P2, P3)	{{`MAX_M{1'b0}} | (1'b1 << P1) | (1'b1 << P2) | (1'b1 << P3) | 1'b1}

/* Return irreducable polynomial */
/* VLSI Aspects on Inversion in Finite Fields, Mikael Olofsson */
`define BCH_POLYNOMIAL(P)	(({ 		\
	`BCH_P3(1),		/* m=2 */	\
	`BCH_P3(1),				\
	`BCH_P3(1),				\
	`BCH_P3(2),		/* m=5 */	\
	`BCH_P3(1),				\
	`BCH_P3(1),				\
	`BCH_P5(4, 3, 2),			\
	`BCH_P3(4),				\
	`BCH_P3(3),				\
	`BCH_P3(2),		/* m=10 */	\
	`BCH_P5(6, 4, 1),			\
	`BCH_P5(4, 3, 1),			\
	`BCH_P5(5, 3, 1),			\
	`BCH_P3(1),		/* m=15 */	\
	`BCH_P5(12, 3, 2)			\
} >> ((`MAX_M-P)*`MAX_M)) & {`MAX_M{1'b1}})

/* Multiply by alpha x*l^1 */
`define BCH_MUL1(M, X)		(`BCH_M2N(M) & (((X) << 1'b1) ^ ((((X) >> ((M)-1'b1)) & 1'b1) ? `BCH_POLYNOMIAL(M) : 1'b0)))


`endif
