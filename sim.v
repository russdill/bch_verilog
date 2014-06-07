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
	output reg wrong_now = 0,
	output reg wrong = 0,
	output [K-1:0] data_out
);

`include "bch.vh"

localparam TCQ = 1;
localparam M = n2m(N);

reg [K-1:0] encode_buf = 0;
reg [K-1:0] decode_buf = 0;
reg [N-1:0] flip_buf = 0;
reg [K-1:0] current_buf = 0;
reg last_data_valid = 0;

wire decIn;
wire new_wrong;
wire encoded_data;
wire decoded_data;
wire encoded_first;
wire encoded_last;
wire decoder_in;
wire decode_busy;
wire encode_busy;

assign busy = encode_busy;

wire first = !last_data_valid && output_valid;

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

bch_decode #(N, K, T, OPTION) u_bch_decode(
	.clk(clk),
	.start(encoded_first),
	.busy(decode_busy),
	.data_in(decoder_in),
	.output_valid(output_valid),
	.data_out(decoded_data)
);

assign data_out = first ? stack[K*rd_pos] : decode_buf[0];
assign decoder_in = (encoded_data ^ flip_buf[0]) && !reset;
assign new_wrong = (decoded_data !== data_out && !reset && output_valid) || output_valid === 1'bx || output_valid === 1'bz || (rd_pos == wr_pos && first);

reg [3:0] rd_pos = 0;
reg [3:0] wr_pos = 0;
reg [K*4-1:0] stack = 0;

always @(posedge clk) begin
	if (encode_start && !encode_busy) begin
		stack[K*wr_pos+:K] <= #TCQ data_in;
		wr_pos <= #TCQ (wr_pos + 1) % 4;
	end
	last_data_valid <= #TCQ output_valid;
	if (first) begin
		decode_buf <= #TCQ {1'b0, stack[K*rd_pos+1+:K-1]};
		rd_pos <= #TCQ (rd_pos + 1) % 4;
	end else
		decode_buf <= #TCQ {1'b0, decode_buf[K-1:1]};

	if (!decode_busy) begin
		encode_buf <= #TCQ encode_start ? data_in : {1'b0, encode_buf[K-1:1]};
		flip_buf <= #TCQ encode_start ? error : {1'b0, flip_buf[N-1:1]};
	end

	if (reset)
		wrong <= #TCQ 1'b0;
	else if (new_wrong)
		wrong <= #TCQ 1'b1;
	wrong_now <= #TCQ new_wrong;
end

endmodule
