`timescale 1ns / 1ps

`include "bch_defs.vh"

/* Supports double and single bit errors */
module bch_error_dec #(
	parameter [`BCH_PARAM_SZ-1:0] P = `BCH_SANE,
	parameter BITS = 1,
	parameter REG_RATIO = 1,
	parameter PIPELINE_STAGES = 0
) (
	input clk,
	input start,					/* Latch inputs, start calculating */
	input [`BCH_SYNDROMES_SZ(P)-1:0] syndromes,
	output [`BCH_ERR_SZ(P)-1:0] err_count,		/* Valid during valid cycles */
	output ready,
	output first,					/* First valid output data */
	output last,					/* Last valid output cycle */
	output valid,					/* Outputting data */
	output [BITS-1:0] err
);
	`include "bch.vh"

	localparam TCQ = 1;
	localparam M = `BCH_M(P);
	localparam T = `BCH_T(P);
	localparam _RUNT = `BCH_DATA_BITS(P) % BITS;
	localparam RUNT = _RUNT ? _RUNT : BITS;

	wire [(2*T-1)*M-1:0] expanded;
	wire [`BCH_SIGMA_SZ(P)-1:0] sigma;
	wire [`BCH_SIGMA_SZ(P)*BITS-1:0] chien;
	wire [BITS-1:0] _err;
	wire first_raw;
	wire last_raw;
	wire valid_raw;
	reg [`BCH_ERR_SZ(P)-1:0] err_count_raw = 0;
	wire [BITS-1:0] _err_raw;

	assign err = last ? (_err & {RUNT{1'b1}}) : _err;

	bch_syndrome_expand #(P) u_expand(
		.syndromes(syndromes),
		.expanded(expanded)
	);

	assign sigma = expanded;

	bch_chien #(P, BITS, REG_RATIO) u_chien(
		.clk(clk),
		.start(start),
		.ready(ready),
		.sigma(sigma),
		.chien(chien),
		.first(first_raw),
		.last(last_raw),
		.valid(valid_raw)
	);

	pipeline #(PIPELINE_STAGES) u_out_pipeline [3-1:0] (
		.clk(clk),
		.i({first_raw, last_raw, valid_raw}),
		.o({first, last, valid})
	);

	genvar i;
	if (T == 1) begin : SEC
		/*
		 * SEC sigma(x) = 1 + S_1 * x
		 * No error if S_1 = 0
		 */
		for (i = 0; i < BITS; i = i + 1) begin : BIT
			assign _err_raw[i] = chien[i*(T+1)*M+:M] == 1;
		end

		always @(posedge clk)
			if (start)
				err_count_raw <= #TCQ |syndromes[0+:M];

		if (PIPELINE_STAGES > 1)
			sec_only_supports_1_pipeline_stage u_sos1ps();

		pipeline #(PIPELINE_STAGES) u_err_pipeline [BITS+`BCH_ERR_SZ(P)-1:0] (
			.clk(clk),
			.i({_err_raw, err_count_raw}),
			.o({_err, err_count})
		);

	end else if (T == 2) begin : POW3
		/*
		 * DEC simga(x) = 1 + sigma_1 * x + sigma_2 * x^2 =
		 *		1 + S_1 * x + (S_1^2 + S_3 * S_1^-1) * x^2
		 * No  error  if S_1  = 0, S_3  = 0
		 * one error  if S_1 != 0, S_3  = S_1^3
		 * two errors if S_1 != 0, S_3 != S_1^3
		 * >2  errors if S_1  = 0, S_3 != 0
		 * The below may be a better choice for large circuits (cycles tradeoff)
		 * sigma_1(x) = S_1 + S_1^2 * x + (S_1^3 + S_3) * x^2
		 */
		reg first_cycle = 0;
		wire first_cycle_pipelined;

		if (PIPELINE_STAGES > 2)
			dec_pow3_only_supports_2_pipeline_stages u_dpos2ps();

		for (i = 0; i < BITS; i = i + 1) begin : BIT
			wire [M-1:0] ch1_flipped;
			wire ch1_nonzero_pipelined;
			wire [M-1:0] ch3_flipped;
			wire ch3_nonzero_pipelined;
			wire [M-1:0] ch3_flipped_pipelined;

			wire [M-1:0] power;
			wire [M-1:0] power_pipelined;
			wire [1:0] errors;
			wire [1:0] errors_pipelined;

			/* For each cycle, try flipping the bit */
			assign ch1_flipped = chien[(i*(T+1)+0)*M+:M] ^ !(first_cycle && !i);
			assign ch3_flipped = chien[(i*(T+1)+2)*M+:M] ^ !(first_cycle && !i);

			/* FIXME: Stagger output to eliminate pipeline reg */
			pow3 #(M) u_pow3(
				.in(ch1_flipped),
				.out(power)
			);

			pipeline #(PIPELINE_STAGES > 0) u_power_pipeline [M+M+2-1:0] (
				.clk(clk),
				.i({power, ch3_flipped, |ch1_flipped, |ch3_flipped}),
				.o({power_pipelined, ch3_flipped_pipelined, ch1_nonzero_pipelined, ch3_nonzero_pipelined})
			);

			/* Calculate the number of erros */
			assign errors = ch1_nonzero_pipelined ?
				(power_pipelined == ch3_flipped_pipelined ? 1 : 2) :
				(ch3_nonzero_pipelined ? 3 : 0);

			pipeline #(PIPELINE_STAGES > 1) u_errors_pipeline [2-1:0] (clk, errors, errors_pipelined);

			/*
			 * If flipping reduced the number of errors,
			 * then we found an error
			 */
			assign _err[i] = err_count_raw > errors_pipelined;
		end
		
		pipeline #(PIPELINE_STAGES) u_cycle_pipeline (
			.clk(clk),
			.i(first_cycle),
			.o(first_cycle_pipelined)
		);

		always @(posedge clk) begin
			first_cycle <= #TCQ start;
			if (first_cycle_pipelined)
				err_count_raw <= #TCQ BIT[0].errors_pipelined;
		end

		assign err_count = err_count_raw;

	end else
		dec_only_valid_for_t_less_than_3 u_dovftlt3();
endmodule
