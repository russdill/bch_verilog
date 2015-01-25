/*
 * BCH Encode/Decoder Modules
 *
 * Copyright 2014 - Russ Dill <russ.dill@asu.edu>
 * Distributed under 2-clause BSD license as contained in COPYING file.
 */
`timescale 1ns / 1ps

`include "bch_defs.vh"

/* serial inversionless */
module bch_sigma_bma_noinv #(
	parameter [`BCH_PARAM_SZ-1:0] P = `BCH_SANE
) (
	input clk,
	input start,
	input [`BCH_SYNDROMES_SZ(P)-1:0] syndromes,
	input ack_done,

	output reg done = 0,
	output ready,
	output reg [`BCH_SIGMA_SZ(P)-1:0] sigma = 0,
	output reg [`BCH_ERR_SZ(P)-1:0] err_count = 0
);
	`include "bch.vh"

	localparam TCQ = 1;
	localparam M = `BCH_M(P);
	localparam T = `BCH_T(P);

	reg [`BCH_SIGMA_SZ(P)-M-1:0] beta = 0;
	wire [`BCH_SIGMA_SZ(P)-1:0] sigma_next;
	wire [M-1:0] d_r;
	reg d_r_nonzero = 0;
	reg [M-1:0] d_p = 0;

	wire [T:0] sigma_serial;
	wire [T:2] beta_serial;

	reg dead_cycle = 0;
	reg start_cycle = 0;
	reg penult_cycle = 0;
	reg last_cycle = 0;
	reg last_cycle1 = 0;
	reg start1 = 0;
	reg start2 = 0;
	reg after_start2 = 0;
	reg run = 0;
	reg run1 = 0;
	reg last_cycle1_first = 0;
	reg run2 = 0;
	reg first = 0;
	reg last = 0;

	wire [M-1:0] syn1 = syndromes[0+:M];
	reg syn1_nonzero;
	reg busy = 0;
	reg bsel_thresh = 0;
	reg [`BCH_ERR_SZ(P)-1:0] err_count_next = 0;
	reg bsel = 0;

	wire [`BCH_ERR_SZ(P)-1:0] bch_n;
	counter #(T+1) u_bch_n_counter(
		.clk(clk),
		.reset(start),
		.ce(start2),
		.count(bch_n)
	);

	wire [log2(M-1)-1:0] count;
	localparam COUNT_END = M > 4 ? lfsr_count(log2(M-1), M - 4) : 1;
	if (M > 4) begin
		lfsr_counter #(log2(M-1)) u_cycle_counter(
			.clk(clk),
			.reset(start_cycle),
			.ce(run),
			.count(count)
		);
	end else begin
		reg _count = 0;
		assign count = _count;
		always @(posedge clk)
			_count <= #TCQ start_cycle;
	end

	wire [(2*T-1)*M-1:0] syn_shuffled;
	bch_syndrome_shuffle #(P) u_bch_syndrome_shuffle(
		.clk(clk),
		.start(start),
		.ce(last_cycle1),
		.syndromes(syndromes),
		.syn_shuffled(syn_shuffled)
	);

	assign ready = !busy && (!done || ack_done);

	function [M*(T+1)-1:0] reg_shift;
		input [M*(T+1)-1:0] r;
		integer i;
	begin
		for (i = 0; i < T + 1; i = i + 1)
			reg_shift[i*M+:M] = {r[i*M+:M-1], r[i*M+M-1]};
	end
	endfunction

	always @(posedge clk) begin
		if (dead_cycle || start) begin
			run1 <= #TCQ 1;
			run2 <= #TCQ 0;
			run <= #TCQ 1;
			start1 <= #TCQ 1;
			start2 <= #TCQ 0;
			start_cycle <= #TCQ 1;
			dead_cycle <= #TCQ 0;
		end else if (last_cycle) begin
			run1 <= #TCQ 0;
			run2 <= #TCQ run1 && !last;
			run <= #TCQ run1 && !last;
			start1 <= #TCQ 0;
			start2 <= #TCQ run1 && !last;
			start_cycle <= #TCQ run1 && !last;
			dead_cycle <= #TCQ run2;
		end else begin
			start1 <= #TCQ 0;
			start2 <= #TCQ 0;
			start_cycle <= #TCQ 0;
			dead_cycle <= #TCQ 0;
		end

		if (start)
			first <= #TCQ 1;
		else if (dead_cycle)
			first <= #TCQ 0;

		last_cycle1_first <= #TCQ first && run1 && penult_cycle;
		last_cycle1 <= #TCQ run1 && penult_cycle;

		if (start)
			last <= #TCQ 0;
		else if (dead_cycle)
			last <= #TCQ bch_n == T - 1;

		if (!start && last_cycle && run1 && last)
			done <= #TCQ 1;
		else if (ack_done)
			done <= #TCQ 0;

		if (start)
			busy <= #TCQ 1;
		else if (last_cycle && run1 && last)
			busy <= #TCQ 0;


		penult_cycle <= #TCQ count == COUNT_END;
		last_cycle <= #TCQ penult_cycle;
		after_start2 <= #TCQ start2;

		if (after_start2) begin
			bsel_thresh <= #TCQ bch_n >= err_count;
			err_count_next <= #TCQ 2 * bch_n - err_count + 1;
		end

		/* Mix run2/last_cycle into bsel so we can avoid the
		 * dead cycle control signal */
		bsel <= run2 && penult_cycle && bsel_thresh && d_r_nonzero;

		if (last_cycle1_first) begin
			/* d_r(0) = 1 + S_1 * x */
			/* sigma stores syn1 for us, but its shifiting it around */
			d_p <= #TCQ syn1_nonzero ? reg_shift(sigma[M+:M]) : 1;
			err_count <= #TCQ syn1_nonzero;
		end else if (bsel) begin
			d_p <= #TCQ d_r;
			err_count <= #TCQ err_count_next;
		end

		if (start2)
			d_r_nonzero <= #TCQ |d_r;

		if (start)
			syn1_nonzero <= #TCQ syn1[0];
		else if (!syn1_nonzero)
			/* Sigma[1] keeps and shifts syn1 for us during the first cycle */
			syn1_nonzero <= #TCQ sigma_serial[1];

		/* LUT5 */
		if (start)
			sigma <= #TCQ {syn1, {M-1{1'b0}}, 1'b1};
		else if (dead_cycle)
			sigma <= #TCQ sigma_next;
		else
			sigma <= #TCQ reg_shift(sigma);

		/* LUT5 with CE */
		if (run) begin
			if (last_cycle1_first)
				/* beta(1)(x) = syn1 ? x^2 : x^3 */
				beta <= #TCQ {!syn1_nonzero, {M-1{1'b0}}, syn1_nonzero, {M{1'b0}}};
			else if (bsel)
				beta <= #TCQ reg_shift(sigma);
			else
				beta <= #TCQ beta << 1;
		end
	end

	/* d_r = summation (sigma_i^(r) * S_(2 * r - i + 1))[0..t] */
	serial_standard_multiplier #(M, T+1) d_r_multiplier(
		.clk(clk),
		.reset(start || dead_cycle),
		.ce(run1),
		.parallel_in(syn_shuffled[0+:M*(T+1)]),
		.serial_in(sigma_serial),
		.out(d_r)
	);

	/* sigma^(r)(x) = d_p * sigma^(r-1)(x) - d_r * beta^(r)(x) */
	genvar i;
	for (i = 0; i < T + 1; i = i + 1) begin : SERIAL
		assign sigma_serial[i] = sigma[i*M+M-1];
	end

	/* 2 * M / 4 slices = 7 slices */
	for (i = 0; i < 2; i = i + 1) begin : SIGMA1
		/* LUT3 + reset */
		serial_standard_multiplier #(M) sigma_multiplier (
			.clk(clk),
			.reset(last_cycle1),
			.ce(1'b1),
			.parallel_in(d_p),
			.serial_in(sigma_serial[i]),
			.out(sigma_next[i*M+:M])
		);
	end

	/* (T - 1) * M / 4 slices = 39 */
	for (i = 2; i < T + 1; i = i + 1) begin : SIGMA2
		assign beta_serial[i] = beta[(i-1)*M+M-1];
		/* LUT5 + reset */
		serial_standard_multiplier #(M, 2) sigma_multiplier (
			.clk(clk),
			.reset(last_cycle1),
			.ce(1'b1),
			.parallel_in({d_p, d_r}),
			.serial_in({sigma_serial[i], beta_serial[i]}),
			.out(sigma_next[i*M+:M])
		);
	end
endmodule
