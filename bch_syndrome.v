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
	`include "bch_syndrome.vh"

	localparam TCQ = 1;
	localparam M = `BCH_M(P);

	genvar idx;

	localparam SYN_COUNT = syndrome_count(M, `BCH_T(P));
	localparam CYCLES = PIPELINE_STAGES + (`BCH_CODE_BITS(P)+BITS-1) / BITS;
	localparam DONE = lfsr_count(M, CYCLES - 2);
	localparam REM = `BCH_CODE_BITS(P) % BITS;
	localparam RUNT = BITS - REM;

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
			assign shifted_in = (data_in << RUNT) | (start ? 0 : runt);
			always @(posedge clk)
				if (ce)
					runt <= #TCQ data_in >> REM;
		end else
			assign shifted_in = data_in;
	endgenerate

	/* Pipelined data for method1 */
	pipeline_ce #(PIPELINE_STAGES > 1) u_data_pipeline [BITS] (
		.clk(clk),
		.ce(ce),
		.i(data_in),
		.o(data_pipelined)
	);

	/* Pipelined data for method2 */
	pipeline_ce #(PIPELINE_STAGES > 0) u_shifted_pipeline [BITS] (
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
		if (syndrome_method(M, `BCH_T(P), idx2syn(M, idx)) == 0) begin : METHOD1
			dsynN_method1 #(P, idx, BITS, REG_RATIO, PIPELINE_STAGES) u_syn1a(
				.clk(clk),
				.start(start),
				.start_pipelined(start_pipelined),
				.ce((busy || start) && ce),
				.data_pipelined(data_pipelined),
				.synN(syndromes[idx*M+:M])
			);
		end else begin : METHOD2
			dsynN_method2 #(P, idx, BITS, PIPELINE_STAGES) u_syn2a(
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

/* Syndrome expansion */
module bch_syndrome_expand #(
	parameter [`BCH_PARAM_SZ-1:0] P = `BCH_SANE
) (
	input [`BCH_SYNDROMES_SZ(P)-1:0] syndromes,
	output [(2*T-1)*M-1:0] expanded
);
	`include "bch_syndrome.vh"

	localparam M = `BCH_M(P);
	localparam T = `BCH_T(P);

	genvar dat;

	generate
	for (dat = 1; dat < 2 * T; dat = dat + 1) begin : ASSIGN
		if (syndrome_method(M, T, dat2syn(M, dat)) == 0) begin : METHOD1
			syndrome_expand_method1 #(P) u_expand(
				.in(syndromes[dat2idx(M, dat)*M+:M]),
				.out(expanded[(dat-1)*M+:M])
			);
		end else begin : METHOD2
			syndrome_expand_method2 #(P, dat) u_expand(
				.in(syndromes[dat2idx(M, dat)*M+:M]),
				.out(expanded[(dat-1)*M+:M])
			);
		end
	end
	endgenerate
endmodule

/* Syndrome shuffling */
module bch_syndrome_shuffle #(
	parameter [`BCH_PARAM_SZ-1:0] P = `BCH_SANE
) (
	input clk,
	input start,		/* Accept first syndrome bit */
	input ce,		/* Shuffle cycle */
	input [`BCH_SYNDROMES_SZ(P)-1:0] syndromes,
	output reg [(2*T-1)*M-1:0] syn_shuffled = 0
);

	`include "bch_syndrome.vh"

	localparam TCQ = 1;
	localparam M = `BCH_M(P);
	localparam T = `BCH_T(P);
	genvar i;
	genvar dat;

	wire [(2*`BCH_T(P)-1)*M-1:0] expanded;
	bch_syndrome_expand #(P) u_expand(
		.syndromes(syndromes),
		.expanded(expanded)
	);

	/* Shuffle syndromes */
	generate
	for (i = 0; i < 2*T-1; i = i + 1) begin : s
		if (i == T + 1 && T < 4) begin
			always @(posedge clk)
				if (start)
					syn_shuffled[i*M+:M] <= #TCQ expanded[(3*T-i-2)*M+:M];
		end else begin
			always @(posedge clk)
				if (start)
					syn_shuffled[i*M+:M] <= #TCQ expanded[M*((2*T+1-i)%(2*T-1))+:M];
				else if (ce)
					syn_shuffled[i*M+:M] <= #TCQ syn_shuffled[M*((i+(2*T-3))%(2*T-1))+:M];
		end
	end
	endgenerate
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
		for (i = 0; i < `BCH_SYNDROMES_SZ(P)/M; i = i + 1)
			assign syndrome_zero[i] = |syndromes[i*M+:M];
	endgenerate

	pipeline #(PIPELINE_STAGES > 0) u_sz_pipeline [`BCH_SYNDROMES_SZ(P)/M] (
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
