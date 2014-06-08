`timescale 1ns / 1ps

module sim #(
	parameter N = 15,
	parameter K = 5,
	parameter T = 3,
	parameter OPTION = "SERIAL"
) (
	input clk,
	input reset,
	input [K-1:0] data_in,
	input [N-1:0] error,
	input encode_start,
	output busy,
	output encoded_penult,
	output output_valid,
	output reg wrong = 0,
	output [K-1:0] data_out
);

`include "bch.vh"

localparam TCQ = 1;
localparam M = n2m(N);

reg [K-1:0] encode_buf = 0;
reg [N-1:0] flip_buf = 0;
reg [K-1:0] err_buf = 0;
reg last_data_valid = 0;

wire encoded_data;
wire decoded_data;
wire encoded_first;
wire encoded_last;
wire decoder_in;
wire decode_busy;
wire encode_busy;
wire [2*T*M-1:M] syndromes;
wire [M*(T+1)-1:0] sigma;
wire syn_done;
wire err_start;
wire err_valid;
wire err;
wire ch_start;
wire key_busy;
wire ch_busy;
wire errors_present;
wire [log2(T+1)-1:0] err_count;

assign busy = encode_busy;

localparam STACK_SZ = 5;

reg [STACK_SZ*log2(T+1)-1:0] err_count_stack = 0;
reg [STACK_SZ-1:0] err_present_stack = 0;
reg [STACK_SZ*K-1:0] err_stack = 0;

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
begin
	count = 0;
	while (bits) begin
		count = count + (bits[0] ? 1'b1 : 1'b0);
		bits = bits >> 1;
	end
	bit_count = count;
end
endfunction

always @(posedge clk) begin
	if (encode_start && !encode_busy) begin
		err_stack[K*wr_pos+:K] <= #TCQ error;
		err_count_stack[log2(T+1)*wr_pos+:log2(T+1)] <= #TCQ bit_count(error);
		err_present_stack[wr_pos] <= #TCQ |error;
		wr_pos <= #TCQ (wr_pos + 1) % STACK_SZ;
	end

	if (!decode_busy) begin
		encode_buf <= #TCQ encode_start ? data_in : {1'b0, encode_buf[K-1:1]};
		flip_buf <= #TCQ encode_start ? error : {1'b0, flip_buf[N-1:1]};
	end
end

/* Generate code */
bch_encode #(N, K, T, OPTION) u_bch_encode(
	.clk(clk),
	.start(encode_start),
	.data_in(encode_start ? data_in[0] : encode_buf[1]),
	.data_out(encoded_data),
	.first(encoded_first),
	.last(encoded_last),
	.penult(encoded_penult),
	.accepted(!decode_busy),
	.busy(encode_busy)
);

assign decoder_in = encoded_data ^ flip_buf[0];

/* Process syndromes */
bch_syndrome #(M, T) u_bch_syndrome(
	.clk(clk),
	.start(encoded_first && !decode_busy),
	.busy(decode_busy),
	.data_in(decoder_in),
	.out(syndromes),
	.done(syn_done),
	.accepted(syn_done && !key_busy)
);

/* Test for errors */
bch_errors_present #(M, T, OPTION) u_errors(
	.start(syn_done && !key_busy),
	.syndromes(syndromes),
	.errors_present(errors_present)
);

wire err_present_wrong = syn_done && !key_busy && (errors_present !== err_present_stack[err_present_rd_pos]);

always @(posedge clk) begin
	if (syn_done && !key_busy)
		err_present_rd_pos = (err_present_rd_pos + 1) % STACK_SZ;
end

/* Solve key equation */
bch_key #(M, T, OPTION) u_key(
	.clk(clk),
	.start(syn_done && !key_busy),
	.busy(key_busy),
	.syndromes(syndromes),
	.sigma(sigma),
	.done(ch_start),
	.accepted(ch_start && !ch_busy),
	.err_count(err_count)
);

wire err_count_wrong = ch_start && (err_count !== err_count_stack[err_count_rd_pos*log2(T+1)+:log2(T+1)]);

always @(posedge clk) begin
	if (ch_start)
		err_count_rd_pos = (err_count_rd_pos + 1) % STACK_SZ;
end

/* Locate errors */
bch_error #(M, K, T, OPTION) u_error(
	.clk(clk),
	.start(ch_start && !ch_busy),
	.busy(ch_busy),
	.accepted(1'b1),
	.sigma(sigma),
	.ready(err_start),
	.valid(err_valid),
	.err(err)
);

wire err_done = last_err_valid && !err_valid;
reg last_err_valid = 0;

wire err_wrong = err_done && (err_buf !== err_stack[err_rd_pos*K+:K]);
wire new_wrong = err_count_overflow || err_overflow || err_present_wrong || err_count_wrong || err_wrong;

always @(posedge clk) begin
	last_err_valid <= #TCQ err_valid;
	if (err_start)
		err_buf <= #TCQ {err, {K-1{1'b0}}};
	else if (err_valid)
		err_buf <= #TCQ {err, err_buf[K-1:1]};

	if (err_done)
		err_rd_pos <= #TCQ (err_rd_pos + 1) % STACK_SZ;

	if (reset)
		wrong <= #TCQ 1'b0;
	else if (new_wrong)
		wrong <= #TCQ 1'b1;
end

endmodule
