`timescale 1ns / 1ps

`include "bch_defs.vh"

/* Calculate syndromes for S_j for 1 .. 2t-1 */
module bch_syndrome #(
	parameter [`BCH_PARAM_SZ-1:0] P = `BCH_SANE,
	parameter BITS = 1
) (
	input clk,
	input start,		/* Accept first syndrome bit (assumes ce) */
	input [BITS-1:0] data_in,
	input accepted,
	output busy,
	output [`BCH_SYNDROMES_SZ(P)-1:0] syndromes,
	output done
);
	`include "bch_syndrome.vh"

	localparam TCQ = 1;
	localparam M = `BCH_M(P);

	genvar idx;

	localparam SYN_COUNT = syndrome_count(M, `BCH_T(P));
	localparam CYCLES = (`BCH_CODE_BITS(P)+BITS-1) / BITS;
	localparam DONE = lfsr_count(M, CYCLES - 2);

	wire [M-1:0] count;
	reg busy_internal = 0;
	reg done_internal = 0;
	reg waiting = 0;

	if (CYCLES > 2)	begin : COUNTER
		lfsr_counter #(M) u_counter(
			.clk(clk),
			.reset(start),
			.ce(count != DONE),
			.count(count)
		);
	end else
		assign count = DONE;

	assign busy = waiting && !accepted;
	assign done = done_internal || waiting;

	always @(posedge clk) begin
		if (start) begin
			done_internal <= #TCQ CYCLES == 1;
			busy_internal <= #TCQ CYCLES > 1;
		end else if (busy_internal && count == DONE) begin
			done_internal <= #TCQ 1;
			busy_internal <= #TCQ 0;
		end else
			done_internal <= #TCQ 0;

		if ((busy_internal && count == DONE) || (start && CYCLES == 1))
			waiting <= #TCQ 1;
		else if (accepted)
			waiting <= #TCQ 0;
	end

	/* LFSR registers */
	generate
	for (idx = 0; idx < SYN_COUNT; idx = idx + 1) begin : SYNDROMES
		if (syndrome_method(M, `BCH_T(P), idx2syn(M, idx)) == 0) begin : METHOD1
			dsynN_method1 #(P, idx, BITS) u_syn1a(
				.clk(clk),
				.ce(busy_internal),
				.start(start),
				.data_in(data_in),
				.synN(syndromes[idx*M+:M])
			);
		end else begin : METHOD2
			dsynN_method2 #(P, idx, BITS) u_syn2a(
				.clk(clk),
				.ce(busy_internal),
				.start(start),
				.data_in(data_in),
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

/* Candidate for pipelining */
module bch_errors_present #(
	parameter [`BCH_PARAM_SZ-1:0] P = `BCH_SANE,
	parameter OPTION = "SERIAL"
) (
	input start,
	input [`BCH_SYNDROMES_SZ(P)-1:0] syndromes,
	output errors_present			/* Valid during start cycle */
);
	assign errors_present = start && |syndromes;
endmodule
