/*
 * BCH Encode/Decoder Modules
 *
 * Copyright 2014 - Russ Dill <russ.dill@asu.edu>
 * Distributed under 2-clause BSD license as contained in COPYING file.
 */
`timescale 1ns / 1ps

`include "bch_defs.vh"

/* Calculate syndromes for S_j for 1 .. 2t-1 */
module bch_syndrome #(
	parameter [`BCH_PARAM_SZ-1:0] P = `BCH_SANE,
	parameter BITS = 1,
	parameter REG_RATIO = 1,
	parameter PIPELINE_STAGES = 0
) (
	input clk,
	input start,		/* Accept first syndrome bit (assumes ce) */
	input ce,
	input [BITS-1:0] data_in,
	output ready,
	output [`BCH_SYNDROMES_SZ(P)-1:0] syndromes,
	output reg done = 0
);
	localparam M = `BCH_M(P);
	localparam [`MAX_M*(1<<(`MAX_M-1))-1:0] TBL = syndrome_build_table(M, `BCH_T(P));

	`include "bch_syndrome.vh"

	localparam TCQ = 1;

	genvar idx;

	localparam CYCLES = PIPELINE_STAGES + (`BCH_CODE_BITS(P)+BITS-1) / BITS;
	localparam DONE = lfsr_count(M, CYCLES - 2);
	localparam REM = `BCH_CODE_BITS(P) % BITS;
	localparam RUNT = BITS - REM;
	localparam SYN_COUNT = TBL[0+:`MAX_M];

	wire [M-1:0] count;
	wire [BITS-1:0] data_pipelined;
	wire [BITS-1:0] shifted_in;
	wire [BITS-1:0] shifted_pipelined;
	wire start_pipelined;
	reg busy = 0;

	if (CYCLES > 2) begin : COUNTER
		lfsr_counter #(M) u_counter(
			.clk(clk),
			.reset(start && ce),
			.ce(busy && ce),
			.count(count)
		);
	end else
		assign count = DONE;

	assign ready = !busy;

	always @(posedge clk) begin
		if (ce) begin
			if (start) begin
				done <= #TCQ CYCLES == 1;
				busy <= #TCQ CYCLES > 1;
			end else if (busy && count == DONE) begin
				done <= #TCQ 1;
				busy <= #TCQ 0;
			end else
				done <= #TCQ 0;
		end
	end

	 /*
	  * Method 1 requires data to be aligned to the first transmitted bit,
	  * which is how input is received. Method 2 requires data to be
	  * aligned to the last received bit, so we may need to insert some
	  * zeros in the first word, and shift the remaining bits
	  */
	generate
		if (REM) begin
			reg [RUNT-1:0] runt = 0;
			assign shifted_in = {start ? {RUNT{1'b0}} : runt, data_in[BITS-1:RUNT]};
			always @(posedge clk)
				if (ce)
					runt <= #TCQ data_in;
		end else
			assign shifted_in = data_in;
	endgenerate


	/* Pipelined data for method1 */
	pipeline_ce #(PIPELINE_STAGES > 1) u_data_pipeline [BITS-1:0] (
		.clk(clk),
		.ce(ce),
		.i(data_in),
		.o(data_pipelined)
	);

	/* Pipelined data for method2 */
	pipeline_ce #(PIPELINE_STAGES > 0) u_shifted_pipeline [BITS-1:0] (
		.clk(clk),
		.ce(ce),
		.i(shifted_in),
		.o(shifted_pipelined)
	);

	pipeline_ce #(PIPELINE_STAGES > 1) u_start_pipeline (
		.clk(clk),
		.ce(ce),
		.i(start),
		.o(start_pipelined)
	);

	/* LFSR registers */
	generate
	for (idx = 0; idx < SYN_COUNT; idx = idx + 1) begin : SYNDROMES
		localparam SYN = idx2syn(idx);
		if (syndrome_method(`BCH_T(P), SYN) == 0) begin : METHOD1
			dsynN_method1 #(P, SYN, BITS, REG_RATIO, PIPELINE_STAGES) u_syn1a(
				.clk(clk),
				.start(start),
				.start_pipelined(start_pipelined),
				.ce((busy || start) && ce),
				.data_pipelined(data_pipelined),
				.synN(syndromes[idx*M+:M])
			);
		end else begin : METHOD2
			dsynN_method2 #(P, SYN, syndrome_degree(M, SYN), BITS, PIPELINE_STAGES) u_syn2a(
				.clk(clk),
				.start(start),
				.start_pipelined(start_pipelined),
				.ce((busy || start) && ce),
				.data_in(shifted_in),
				.data_pipelined(shifted_pipelined),
				.synN(syndromes[idx*M+:M])
			);
		end
	end
	endgenerate
endmodule

/* Syndrome expansion/shuffling */
module bch_syndrome_shuffle #(
	parameter [`BCH_PARAM_SZ-1:0] P = `BCH_SANE
) (
	input clk,
	input start,		/* Accept first syndrome bit */
	input ce,		/* Shuffle cycle */
	input [`BCH_SYNDROMES_SZ(P)-1:0] syndromes,
	output reg [(2*`BCH_T(P)-1)*`BCH_M(P)-1:0] syn_shuffled = 0
);
	localparam M = `BCH_M(P);
	localparam [`MAX_M*(1<<(`MAX_M-1))-1:0] TBL = syndrome_build_table(M, `BCH_T(P));

	`include "bch_syndrome.vh"

	localparam TCQ = 1;
	localparam T = `BCH_T(P);

	genvar i;

	wire [(2*T-1)*M-1:0] bypass_in_shifted;
	wire [(2*T-1)*M-1:0] syndromes_pre_expand;
	wire [(2*T-1)*M-1:0] expand_in;
	wire [(2*T-1)*M-1:0] expand_in1;
	wire [(2*T-1)*M-1:0] syn_expanded;

	for (i = 0; i < 2 * T - 1; i = i + 1) begin : ASSIGN
		assign syndromes_pre_expand[i*M+:M] = syndromes[dat2idx(i+1)*M+:M] & {M{start}};
	end

	/* Shuffle syndromes */
	rotate_right #((2*T-1)*M, 3*M) u_rol_e(syndromes_pre_expand, expand_in1);
	reverse_words #(M, 2*T-1) u_rev(expand_in1, expand_in);

	rotate_left #((2*T-1)*M, 2*M) u_rol_b(syn_shuffled, bypass_in_shifted);

	/*
	 * We need to combine syndrome expansion and shuffling into a single
	 * operation so we can optimize LUT usage for an XOR carry chain. It
	 * causes a little confusion as we need to select expansion method
	 * based on the pre-shuffled indexes as well as pass in the pre-
	 * shuffled index to the expand method.
	 */
	for (i = 0; i < 2 * T - 1; i = i + 1) begin : EXPAND
		localparam PRE = (2 * T - 1 + 2 - i) % (2 * T - 1); /* Pre-shuffle value */
		if (syndrome_method(T, dat2syn(PRE+1)) == 0) begin : METHOD1
			syndrome_expand_method1 #(P) u_expand(
				.in(expand_in[i*M+:M]),
				.out(syn_expanded[i*M+:M])
			);
		end else begin : METHOD2
			syndrome_expand_method2 #(P, PRE+1) u_expand(
				.in(expand_in[i*M+:M]),
				.out(syn_expanded[i*M+:M])
			);
		end
	end

	always @(posedge clk)
		if (start || ce)
			syn_shuffled <= #TCQ syn_expanded ^ ({(2*T-1)*M{!start}} & bypass_in_shifted);
endmodule

module bch_errors_present #(
	parameter [`BCH_PARAM_SZ-1:0] P = `BCH_SANE,
	parameter PIPELINE_STAGES = 0
) (
	input clk,
	input start,
	input [`BCH_SYNDROMES_SZ(P)-1:0] syndromes,
	output done,
	output errors_present			/* Valid during done cycle */
);
	localparam M = `BCH_M(P);
	genvar i;

	wire [(`BCH_SYNDROMES_SZ(P)/M)-1:0] syndrome_zero;
	wire [(`BCH_SYNDROMES_SZ(P)/M)-1:0] syndrome_zero_pipelined;

	generate
		for (i = 0; i < `BCH_SYNDROMES_SZ(P)/M; i = i + 1) begin : ZEROS
			assign syndrome_zero[i] = |syndromes[i*M+:M];
		end
	endgenerate

	pipeline #(PIPELINE_STAGES > 0) u_sz_pipeline [`BCH_SYNDROMES_SZ(P)/M-1:0] (
		.clk(clk),
		.i(syndrome_zero),
		.o(syndrome_zero_pipelined)
	);

	pipeline #(PIPELINE_STAGES > 1) u_present_pipeline (
		.clk(clk),
		.i(|syndrome_zero_pipelined),
		.o(errors_present)
	);

	pipeline #(PIPELINE_STAGES) u_done_pipeline (
		.clk(clk),
		.i(start),
		.o(done)
	);
endmodule
