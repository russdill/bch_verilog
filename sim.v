`timescale 1ns / 1ps

`include "bch_defs.vh"

module sim #(
	parameter [`BCH_PARAM_SZ-1:0] P = `BCH_SANE,
	parameter OPTION = "SERIAL",
	parameter BITS = 1,
	parameter REG_RATIO = 1
) (
	input clk,
	input reset,
	input [`BCH_DATA_BITS(P)-1:0] data_in,
	input [`BCH_CODE_BITS(P)-1:0] error,
	input encode_start,
	output busy,
	output reg wrong = 0
);

`include "bch.vh"

localparam TCQ = 1;
localparam N = `BCH_N(P);
localparam E = `BCH_ECC_BITS(P);
localparam M = `BCH_M(P);
localparam T = `BCH_T(P);
localparam K = `BCH_K(P);
localparam B = `BCH_DATA_BITS(P);

if (`BCH_DATA_BITS(P) % BITS)
	sim_only_supports_factors_of_BCH_DATA_BITS_for_BITS u_sosfobdbfb();

reg [B-1:0] encode_buf = 0;
reg [E+B-1:0] flip_buf = 0;
reg [B-1:0] err_buf = 0;
reg last_data_valid = 0;

wire [BITS-1:0] encoded_data;
wire encoded_first;
wire encoded_last;
wire [BITS-1:0] decoder_in;
wire decode_ready;
wire encode_ready;
wire [`BCH_SYNDROMES_SZ(P)-1:0] syndromes;
wire syn_done;
wire err_first;
wire err_last;
wire err_valid;
wire [BITS-1:0] err;
wire key_ready;
wire errors_present;
wire [`BCH_ERR_SZ(P)-1:0] err_count;

assign busy = !encode_ready && (!syn_done || key_ready);

localparam STACK_SZ = 16;//6;

reg [STACK_SZ*`BCH_ERR_SZ(P)-1:0] err_count_stack = 0;
reg [STACK_SZ-1:0] err_present_stack = 0;
reg [STACK_SZ*`BCH_DATA_BITS(P)-1:0] err_stack = 0;

reg [log2(STACK_SZ)-1:0] wr_pos = 0;
reg [log2(STACK_SZ)-1:0] err_count_rd_pos = 0;
reg [log2(STACK_SZ)-1:0] err_present_rd_pos = 0;
reg [log2(STACK_SZ)-1:0] err_rd_pos = 0;

wire err_count_overflow = ((wr_pos + 1) % STACK_SZ) === err_count_rd_pos;
wire err_present_overflow = ((wr_pos + 1) % STACK_SZ) === err_present_rd_pos;
wire err_overflow = ((wr_pos + 1) % STACK_SZ) === err_rd_pos;

function integer bit_count;
	input [N-1:0] bits;
	integer count;
	integer i;
begin
	count = 0;
	for (i = 0; i < N; i = i + 1) begin
		count = count + bits[i];
	end
	bit_count = count;
end
endfunction

always @(posedge clk) begin
	if (encode_start && encode_ready && (!syn_done || key_ready)) begin
		err_stack[B*wr_pos+:B] <= #TCQ error;
		err_count_stack[`BCH_ERR_SZ(P)*wr_pos+:`BCH_ERR_SZ(P)] <= #TCQ bit_count(error);
		err_present_stack[wr_pos] <= #TCQ |error;
		wr_pos <= #TCQ (wr_pos + 1) % STACK_SZ;
	end

	if (encode_start && encode_ready && (!syn_done || key_ready)) begin
		encode_buf <= #TCQ data_in;
		flip_buf   <= #TCQ error;
	end else if (!encode_ready) begin
		encode_buf <= #TCQ encode_buf >> BITS;
		flip_buf   <= #TCQ flip_buf >> BITS;
	end
end

wire [BITS-1:0] encoder_in = encode_start ? data_in : (encode_buf >> BITS);

/* Generate code */
bch_encode #(P, BITS) u_bch_encode(
	.clk(clk),

	/* Don't assert start until we get the ready signal*/
	.start(encode_start && encode_ready),
	.ready(encode_ready),

	/* Keep adding data until the decoder is busy */
	.ce(!syn_done || key_ready),

	.data_in(encoder_in),
	.data_out(encoded_data),
	.data_bits(),
	.ecc_bits(),
	.first(encoded_first),
	.last(encoded_last)
);

assign decoder_in = encoded_data ^ (encoded_first ? error : (flip_buf >> BITS));

/* Process syndromes */
bch_syndrome #(P, BITS, REG_RATIO) u_bch_syndrome(
	.clk(clk),

	/* Don't assert start until we get the ready signal */
	.start(encoded_first && decode_ready),
	.ready(decode_ready),

	/* Keep adding data until the next stage is busy */
	.ce(!syn_done || key_ready),

	.data_in(decoder_in),
	.syndromes(syndromes),
	.done(syn_done)
);

/* Test for errors */
bch_errors_present #(P) u_errors(
	.clk(clk),
	.start(syn_done && key_ready),
	.syndromes(syndromes),
	.done(errors_present_done),
	.errors_present(errors_present)
);

wire err_present_wrong = errors_present_done && (errors_present !== err_present_stack[err_present_rd_pos]);

always @(posedge clk) begin
	if (errors_present_done)
		err_present_rd_pos = (err_present_rd_pos + 1) % STACK_SZ;
end

wire err_count_wrong;
if (T > 1 && (OPTION == "SERIAL" || OPTION == "PARALLEL")) begin : TMEC

	wire ch_start;
	wire ch_ready;
	wire [`BCH_SIGMA_SZ(P)-1:0] sigma;

	/* Solve key equation */
	if (OPTION == "SERIAL") begin : BMA_SERIAL
		bch_sigma_bma_serial #(P) u_bma (
			.clk(clk),
			.start(syn_done && key_ready),
			.ready(key_ready),
			.syndromes(syndromes),
			.sigma(sigma),
			.done(ch_start),
			.ack_done(ch_ready),
			.err_count(err_count)
		);
	end else if (OPTION == "PARALLEL") begin : BMA_PARALLEL
		bch_sigma_bma_parallel #(P) u_bma (
			.clk(clk),
			.start(syn_done && key_ready),
			.ready(key_ready),
			.syndromes(syndromes),
			.sigma(sigma),
			.done(ch_start),
			.ack_done(ch_ready),
			.err_count(err_count)
		);
	end

	assign err_count_wrong = ch_start && (err_count !== err_count_stack[err_count_rd_pos*`BCH_ERR_SZ(P)+:`BCH_ERR_SZ(P)]);
	always @(posedge clk) begin
		if (ch_start && ch_ready)
			err_count_rd_pos <= #TCQ (err_count_rd_pos + 1) % STACK_SZ;
	end

	/* Locate errors */
	bch_error_tmec #(P, BITS, REG_RATIO) u_error_tmec(
		.clk(clk),
		.start(ch_start && ch_ready),
		.ready(ch_ready),
		.sigma(sigma),
		.first(err_first),
		.last(err_last),
		.valid(err_valid),
		.err(err)
	);

end else begin : DEC

	/* Locate errors */
	bch_error_dec #(P, BITS, REG_RATIO) u_error_dec(
		.clk(clk),
		.start(syn_done && key_ready),
		.ready(key_ready),
		.syndromes(syndromes),
		.first(err_first),
		.last(err_last),
		.valid(err_valid),
		.err(err),
		.err_count(err_count)
	);

	assign err_count_wrong = err_first && (err_count !== err_count_stack[err_count_rd_pos*`BCH_ERR_SZ(P)+:`BCH_ERR_SZ(P)]);
	always @(posedge clk) begin
		if (err_first)
			err_count_rd_pos <= #TCQ (err_count_rd_pos + 1) % STACK_SZ;
	end

end

reg err_done = 0;

wire err_wrong = err_done && (err_buf !== err_stack[err_rd_pos*B+:B]);
wire new_wrong = err_count_overflow || err_overflow || err_present_wrong || err_count_wrong || err_wrong;

always @(posedge clk) begin
	if (err_first)
		err_buf <= #TCQ err << (`BCH_DATA_BITS(P) - BITS);
	else if (err_valid)
		err_buf <= #TCQ (err << (`BCH_DATA_BITS(P) - BITS)) | (err_buf >> BITS);

	err_done <= #TCQ err_last;
	if (err_done)
		err_rd_pos <= #TCQ (err_rd_pos + 1) % STACK_SZ;

	if (reset)
		wrong <= #TCQ 1'b0;
	else if (new_wrong)
		wrong <= #TCQ 1'b1;
end

endmodule
