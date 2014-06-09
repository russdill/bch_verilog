`define MAX_M			16
`define BCH_PARAM_MASK		((1 << `MAX_M) - 1)
`define BCH_PARAM(P, IDX)	(((P) >> (`MAX_M*IDX)) & `BCH_PARAM_MASK)
`define BCH_PARAM_SZ		(`MAX_M*5)

`define BCH_M(P)		`BCH_PARAM(P, 0)
`define BCH_N(P)		`BCH_PARAM(P, 1)
`define BCH_K(P)		`BCH_PARAM(P, 2)
`define BCH_T(P)		`BCH_PARAM(P, 3)
`define BCH_DATA_BITS(P)	`BCH_PARAM(P, 4)
`define BCH_ECC_BITS(P)		(`BCH_N(P) - `BCH_K(P))
`define BCH_CODE_BITS(P)	(`BCH_ECC_BITS(P) + `BCH_DATA_BITS(P))
`define BCH_SYNDROMES_SZ(P)	((2*`BCH_T(P) - 1)*`BCH_M(P))
`define BCH_SIGMA_SZ(P)		((`BCH_T(P)+1)*`BCH_M(P))
`define BCH_ERR_SZ(P)		log2(`BCH_T(P)+1)

`define BCH_PARAMS(M, N, K, T, B)	((M) | ((N) << `MAX_M) | ((K) << (`MAX_M*2)) | ((T) << (`MAX_M*3)) | ((B) << (`MAX_M*4)))
`define BCH_SANE		`BCH_PARAMS(4, 15, 7, 2, 7)
