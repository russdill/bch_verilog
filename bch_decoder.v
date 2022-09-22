/*
 * BCH Encode/Decoder Modules
 *
 * Copyright 2014 - Russ Dill <russ.dill@asu.edu>
 * Distributed under 2-clause BSD license as contained in COPYING file.
 */
`timescale 1ns / 1ps



module bch_decoder #(
	parameter T = 3,
	parameter DATA_BITS = 5,
	parameter BITS = 1,
	parameter SYN_REG_RATIO = 1,
	parameter ERR_REG_RATIO = 1,
	parameter SYN_PIPELINE_STAGES = 0,
	parameter ERR_PIPELINE_STAGES = 0,
	parameter ACCUM = 1,
	parameter NCHANNEL = 4,
	parameter NKEY = 2,
	parameter NCHIEN = 1
) (
	input clk,
	input [NCHANNEL*BITS-1:0] data,
	input [NCHANNEL-1:0] syn_start,
	output [NCHANNEL-1:0] syn_ready,
	output reg [NCHANNEL*BITS-1:0] err_out = 0,
	output reg [NCHANNEL-1:0] first_out = 0
);
	`include "bch_params.vh"
	localparam TCQ = 1;
	localparam BCH_PARAMS = bch_params(DATA_BITS, T);
	localparam NREDUCED = NKEY - NCHIEN;

	parameter CHANNEL_SZ = $clog2(NCHANNEL+1);
	parameter KEY_SZ = $clog2(NKEY+1);

	wire [NCHANNEL*`BCH_SYNDROMES_SZ(BCH_PARAMS)-1:0] syndromes;
	wire [NCHANNEL-1:0] syn_done;
	reg [NCHANNEL-1:0] syn_full = 0;

	bch_syndrome #(BCH_PARAMS, BITS, SYN_REG_RATIO, SYN_PIPELINE_STAGES) u_bch_syndrome [NCHANNEL-1:0] (
		.clk(clk),
		.start(syn_start && syn_ready),
		.ready(syn_ready),
		.ce(1'b1),
		.data_in(data),
		.syndromes(syndromes),
		.done(syn_done)
	);

	/* Round robin accept syndromes */
	reg [CHANNEL_SZ-1:0] channel = 0;
	reg [CHANNEL_SZ-1:0] curr_channel = 0;
	reg [NKEY*CHANNEL_SZ-1:0] key_channel = 0;
	reg [KEY_SZ-1:0] key_in = 0;
	reg [`BCH_SYNDROMES_SZ(BCH_PARAMS)-1:0] syndrome = 0;
	reg ready = 1;
	reg err_pres_check = 0;
	reg [NCHANNEL-1:0] do_skip = 0;	/* Output channel should do a skip */
	reg [NCHANNEL-1:0] do_full = 0;	/* Output channel should output from mux */

	wire errors_present_done;
	reg errors_present_done_sticky = 0;
	wire errors_present;
	wire [`BCH_SYNDROMES_SZ(BCH_PARAMS)-1:0] syndrome_sel;
	wire [NKEY-1:0] key_ready;

	mux #(NCHANNEL, `BCH_SYNDROMES_SZ(BCH_PARAMS)) u_syndrome_mux (
		.in(syndromes),
		.sel(channel),
		.out(syndrome_sel)
	);

	bch_errors_present #(BCH_PARAMS, 2) u_errors (
		.clk(clk),
		.start(err_pres_check),
		.syndromes(syndrome),
		.done(errors_present_done),
		.errors_present(errors_present)
	);

	always @(posedge clk) begin
		do_skip <= #TCQ 0;

		if (ready) begin
			/* Wait for the next available syndrome */
			if (syn_done[channel]) begin
				syndrome <= #TCQ syndrome_sel;
				ready <= #TCQ 0;
				err_pres_check <= #TCQ 1;
				if (channel == NCHANNEL - 1)
					channel <= #TCQ 0;
				else
					channel <= #TCQ channel + 1'b1;
				curr_channel <= #TCQ channel;
			end else
				err_pres_check <= #TCQ 0;

			errors_present_done_sticky <= #TCQ 0;
		end else begin
			err_pres_check <= #TCQ 0;

			if (errors_present_done && !errors_present) begin
				/* Syndrome was empty, skip */
				ready <= #TCQ 1;
				errors_present_done_sticky <= #TCQ 0;
				do_skip[curr_channel] <= #TCQ 1;
			end else if (errors_present_done || errors_present_done_sticky) begin
				/* We have a syndrome, wait for the next key solver */
				if (key_ready[key_in]) begin
					ready <= #TCQ 1;
					key_channel[key_in*CHANNEL_SZ+:CHANNEL_SZ] <= #TCQ curr_channel;
					if (key_in == NKEY - 1)
						key_in <= #TCQ 0;
					else
						key_in <= #TCQ key_in + 1'b1;
					errors_present_done_sticky <= #TCQ 0;
				end else
					errors_present_done_sticky <= #TCQ 1;
			end
		end
	end

	wire [NKEY-1:0] key_start;

	genvar i;
	generate
	for (i = 0; i < NKEY; i = i + 1) begin : KEY_START
		assign key_start[i] = (errors_present_done && errors_present) ||
			errors_present_done_sticky && i == key_in;
	end
	endgenerate

	wire [NKEY-1:0] key_done;
	wire [NKEY*`BCH_SIGMA_SZ(BCH_PARAMS)-1:0] sigma;
	wire [NKEY*`BCH_ERR_SZ(BCH_PARAMS)-1:0] err_count;
	wire [NKEY-1:0] key_ack_done;

	bch_sigma_bma_serial #(BCH_PARAMS) u_bma [NKEY-1:0] (
		.clk(clk),
		.start(key_start),
		.ready(key_ready),
		.syndromes(syndrome),
		.sigma(sigma),
		.done(key_done),
		.ack_done(key_ack_done),
		.err_count(err_count)
	);

	/* Round robin accept key output */
	reg [`BCH_SIGMA_SZ(BCH_PARAMS)-1:0] curr_sigma = 1;
	reg [KEY_SZ-1:0] key_out = 0;
	reg ready_out = 1;
	reg [`BCH_ERR_SZ(BCH_PARAMS)-1:0] curr_err_count = 0;
	reg [$clog2(NCHIEN+1)-1:0] chien = 0;
	reg [$clog2(NREDUCED+1)-1:0] reduced = 0;
	reg [CHANNEL_SZ-1:0] curr_key_channel = 0;

	reg [NCHIEN-1:0] chien_busy = 0;
	reg [NREDUCED-1:0] reduced_busy = 0;
	reg [NCHIEN-1:0] chien_start = 0;
	reg [NREDUCED-1:0] reduced_start = 0;
	reg [NCHIEN*CHANNEL_SZ-1:0] chien_channel = 0;
	reg [NREDUCED*CHANNEL_SZ-1:0] reduced_channel = 0;

	wire [NCHANNEL-1:0] output_last;
	reg [NCHANNEL*KEY_SZ-1:0] output_mux = 0;

	wire [`BCH_SIGMA_SZ(BCH_PARAMS)-1:0] sigma_sel;
	wire [CHANNEL_SZ-1:0] key_channel_sel;
	wire [`BCH_ERR_SZ(BCH_PARAMS)-1:0] err_count_sel;

	generate
	for (i = 0; i < NKEY; i = i + 1) begin : KEY_ACK
		assign key_ack_done[i] = i == key_out && ready_out;
	end
	endgenerate

	mux #(NKEY, `BCH_SIGMA_SZ(BCH_PARAMS)) u_sigma_mux(sigma, key_out, sigma_sel);
	mux #(NKEY, CHANNEL_SZ) u_key_channel_mux(key_channel, key_in, key_channel_sel);
	mux #(NKEY, `BCH_ERR_SZ(BCH_PARAMS)) u_err_count_mux(err_count, key_out, err_count_sel);

	/* FIXME: In !NREDUCED case, we can line them up 1 to 1, avoiding crossbar/RR */
	always @(posedge clk) begin
		do_full <= #TCQ 0;
		chien_start <= #TCQ 0;
		if (NREDUCED) begin
			reduced_start <= #TCQ 0;
		end

		if (ready_out) begin
			/* Get the next ready polynomial equation */
			if (key_done[key_out]) begin
				curr_sigma <= #TCQ sigma_sel;
				curr_key_channel <= #TCQ key_channel_sel;
				curr_err_count <= #TCQ err_count_sel;
				ready_out <= #TCQ 0;
				if (key_out == NKEY - 1)
					key_out <= #TCQ 0;
				else
					key_out <= #TCQ key_out + 1'b1;
			end
		end else begin
			/* Get the next chien unit */
			if (NREDUCED && curr_err_count == 1) begin
				/* Reduced */
				if (!reduced_busy[reduced]) begin
					do_full[curr_key_channel] <= #TCQ 1;
					output_mux[curr_key_channel*KEY_SZ+:KEY_SZ] <= #TCQ reduced + NCHIEN;
					reduced_channel[reduced*CHANNEL_SZ+:CHANNEL_SZ] <= #TCQ curr_key_channel;
					reduced_start[reduced] <= #TCQ 1;
					ready_out <= #TCQ 1;
					if (reduced == NREDUCED - 1)
						reduced <= #TCQ 0;
					else
						reduced <= #TCQ reduced + 1'b1;
				end
			end else begin
				/* Traditional */
				if (!chien_busy[chien]) begin
					do_full[curr_key_channel] <= #TCQ 1;
					output_mux[curr_key_channel*KEY_SZ+:KEY_SZ] <= #TCQ chien;
					chien_channel[chien*CHANNEL_SZ+:CHANNEL_SZ] <= #TCQ curr_key_channel;
					chien_start[chien] <= #TCQ 1;
					ready_out <= #TCQ 1;
					if (chien == NCHIEN - 1)
						chien <= #TCQ 0;
					else
						chien <= #TCQ chien + 1'b1;
				end
			end
		end
	end

	wire [NCHIEN-1:0] chien_first;
	wire [BITS*NCHIEN-1:0] chien_err;

	bch_error_tmec #(BCH_PARAMS, BITS, ERR_REG_RATIO, ERR_PIPELINE_STAGES, ACCUM) u_error_tmec [NCHIEN-1:0] (
		.clk(clk),
		.start(chien_start),
		.sigma(curr_sigma),
		.first(chien_first),
		.err(chien_err)
	);

	generate
	for (i = 0; i < NCHIEN; i = i + 1) begin : CHIEN_BUSY
		wire [CHANNEL_SZ-1:0] n;
		assign n = chien_channel[i*CHANNEL_SZ+:CHANNEL_SZ];
		always @(posedge clk) begin
			if (chien_start[i])
				chien_busy[i] <= #TCQ 1;
			else if (output_last[n])
				chien_busy[i] <= #TCQ 0;
		end
	end

	wire [NREDUCED-1:0] reduced_first;
	wire [BITS*NREDUCED-1:0] reduced_err;

	if (NREDUCED) begin
		bch_error_one #(BCH_PARAMS, BITS, ERR_PIPELINE_STAGES) u_error_one [NREDUCED-1:0] (
			.clk(clk),
			.start(reduced_start),
			.sigma(curr_sigma[`BCH_M(BCH_PARAMS)*2-1:0]),
			.first(reduced_first),
			.err(reduced_err)
		);

		for (i = 0; i < NREDUCED; i = i + 1) begin : REDUCED_BUSY
			wire [CHANNEL_SZ-1:0] n;
			assign n = reduced_channel[i*CHANNEL_SZ+:CHANNEL_SZ];
			always @(posedge clk) begin
				if (reduced_start[i])
					reduced_busy[i] <= #TCQ 1;
				else if (output_last[n])
					reduced_busy[i] <= #TCQ 0;
			end
		end
	end
	endgenerate

	/* Combine two solvers */
	wire [NKEY-1:0] first;
	wire [BITS*NKEY-1:0] err;

	assign err = {reduced_err, chien_err};
	assign first = {reduced_first, chien_first};

	/* Output stages */
	generate
	for (i = 0; i < NCHANNEL; i = i + 1) begin : CHANNEL
		reg busy = 0;
		reg queue_skip = 0;
		reg skipping = 0;
		reg full = 0;
		wire [KEY_SZ-1:0] mux;
		wire valid;

		assign mux = output_mux[i*KEY_SZ+:KEY_SZ];

		bch_chien_counter #(BCH_PARAMS, BITS) u_error_count (
			.clk(clk),
			.first(!busy && (do_full[i] || queue_skip)),
			.valid(valid),
			.last(output_last[i])
		);

		always @(posedge clk) begin
			err_out[i*BITS+:BITS] <= #TCQ err[mux*BITS+:BITS];

			first_out[i] <= #TCQ (full && first[mux]) || (queue_skip && !busy);

			/* Make sure we catch it in case it comes in while we
			 * are busy */
			if (do_skip[i])
				queue_skip <= #TCQ 1;

			if (busy) begin
				if (output_last[i]) begin
					busy <= #TCQ 0;
					skipping <= #TCQ 0;
					full <=# TCQ 0;
				end
			end else if (queue_skip) begin
				queue_skip <= #TCQ 0;
				busy <= #TCQ 1;
				skipping <= #TCQ 1;
			end else if (do_full[i]) begin
				busy <= #TCQ 1;
				full <= #TCQ 1;
			end
		end
		
	end
	endgenerate


endmodule

