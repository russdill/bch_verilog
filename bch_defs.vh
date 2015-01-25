/*
 * BCH Encode/Decoder Modules
 *
 * Copyright 2014 - Russ Dill <russ.dill@asu.edu>
 * Distributed under 2-clause BSD license as contained in COPYING file.
 */
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
`define BCH_CHIEN_SZ(P)		((`BCH_T(P)+1)*`BCH_M(P))
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
	`BCH_P3(3),		/* m=10 */	\
	`BCH_P3(2),				\
	`BCH_P5(6, 4, 1),			\
	`BCH_P5(4, 3, 1),			\
	`BCH_P5(5, 3, 1),			\
	`BCH_P3(1),		/* m=15 */	\
	`BCH_P5(5, 3, 2)			\
} >> ((`MAX_M-P)*`MAX_M)) & {`MAX_M{1'b1}})

/* For trinomials, selection of a dual basis is easy */
`define BCH_D_P3(P)		{{`MAX_M{1'b0}} | (1'b1 << (P - 1))}

/* For pentanomials, an optimal dual basis is defined for each M */
`define BCH_D_P5(P)		{{`MAX_M{1'b0}} | P}

/*
 * Calculated XOR gates required for different dual basis values. Values
 * are chosen so that they generate a matrix with an upper and lower
 * matix that are both easily inverted for conerting back to standard basis
 *
 *         sd/ds
 * M = 8
 *   min    2/2  @ b101
 * M = 12
 *   min    7/6  @ b111
 *   min    8/5  @ b1111
 * M = 13
 *   min    4/3  @ b111
 * M = 14
 *   min    5/4  @ b111
 * M = 16
 *   min    3/3  @ b101
 */

`define BCH_DUAL(P)		(({ 		\
	`BCH_D_P3(1),		/* m=2 */	\
	`BCH_D_P3(1),				\
	`BCH_D_P3(1),				\
	`BCH_D_P3(2),		/* m=5 */	\
	`BCH_D_P3(1),				\
	`BCH_D_P3(1),				\
	`BCH_D_P5(3'b101),			\
	`BCH_D_P3(4),				\
	`BCH_D_P3(3),		/* m=10 */	\
	`BCH_D_P3(2),				\
	`BCH_D_P5(4'b1111),			\
	`BCH_D_P5(3'b111),			\
	`BCH_D_P5(3'b111),			\
	`BCH_D_P3(1),		/* m=15 */	\
	`BCH_D_P5(3'b101)			\
} >> ((`MAX_M-P)*`MAX_M)) & {`MAX_M{1'b1}})

/* Degree of dual basis */
`define BCH_DUALD(M)		(log2(`BCH_DUAL(M)) - 1)

/* Multiply by alpha x*l^1 */
`define BCH_MUL_POLY(M, X, POLY)	(`BCH_M2N(M) & (((X) << 1'b1) ^ ((((X) >> ((M)-1'b1)) & 1'b1) ? POLY : 1'b0)))

/* Multiply by alpha x*l^1 */
`define BCH_MUL1(M, X)		`BCH_MUL_POLY(M, X, `BCH_POLYNOMIAL(M))

`define BCH_BIT_SEL(N, D)	(((D) >> (N)) & 1)
`define BCH_EACH_BIT(FN, OP, D)	(`FN(15,(D)) OP `FN(14,(D)) OP	\
				`FN(13,(D)) OP `FN(12,(D)) OP	\
				`FN(11,(D)) OP `FN(10,(D)) OP	\
				`FN(9,(D)) OP `FN(8,(D)) OP	\
				`FN(7,(D)) OP `FN(6,(D)) OP	\
				`FN(5,(D)) OP `FN(4,(D)) OP	\
				`FN(3,(D)) OP `FN(2,(D)) OP	\
				`FN(1,(D)) OP `FN(0,(D)))
`define BCH_NBITS(D)	`BCH_EACH_BIT(BCH_BIT_SEL, +, D)

/*
 * Non-zero if irreducible polynomial is of the form x^m + x^P1 + x^P2 + x^P3 + 1
 * zero for x^m + x^P + 1
 */
`define BCH_IS_PENTANOMIAL(M)	(`BCH_NBITS(`BCH_POLYNOMIAL(M)) == 4)

`endif
