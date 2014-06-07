`timescale 1ns / 1ps

module bch_decode #(
	parameter N = 15,
	parameter K = 5,
	parameter T = 3,	/* Correctable errors */
	parameter OPTION = "SERIAL"
) (
	input clk,
	input start,
	input data_in,
	output busy,
	output reg output_valid = 0,
	output reg data_out = 0
);

`include "bch.vh"

localparam TCQ = 1;
localparam M = n2m(N);
localparam BUF_SIZE = T < 3 ? (N + 2) : (OPTION == "SERIAL" ? (N + T * (M + 2) + 0) : (N + T*2 + 1)); /* cycles required */

wire [2*T*M-1:M] syndromes;
wire [M*(T+1)-1:0] sigma;
wire syn_done;
wire err_start;
wire err_valid;
wire err;
wire ch_start;
wire key_busy;
wire ch_busy;

/* Process syndromes */
bch_syndrome #(M, T) u_bch_syndrome(
	.clk(clk),
	.start(start && !busy),
	.busy(busy),
	.data_in(data_in),
	.out(syndromes),
	.done(syn_done),
	.accepted(syn_done && !key_busy)
);

/* Solve key equation */
bch_key #(M, T, OPTION) u_key(
	.clk(clk),
	.start(syn_done && !key_busy),
	.busy(key_busy),
	.syndromes(syndromes),
	.sigma(sigma),
	.done(ch_start),
	.accepted(ch_start && !ch_busy)
);

/* Locate errors */
bch_error #(M, K, T) u_error(
	.clk(clk),
	.start(ch_start && !ch_busy),
	.busy(ch_busy),
	.accepted(1'b1),
	.sigma(sigma),
	.ready(err_start),
	.valid(err_valid),
	.err(err)
);

reg [N-1:0] buf_in = 0;
reg [K-1:0] buf_pipeline = 0;
reg [K-1:0] buf_err = 0;

always @(posedge clk) begin
	if (start && !busy)
		buf_in <= #TCQ {data_in, {N-1{1'b0}}};
	else if (!busy)
		buf_in <= #TCQ {data_in, buf_in[N-1:1]};

	if (syn_done && !key_busy)
		buf_pipeline <= #TCQ buf_in;

	if (ch_start)
		buf_err <= #TCQ (T < 3) ? buf_in : buf_pipeline;

	else if (err_valid)
		buf_err <= #TCQ {1'b0, buf_err[K-1:1]};

	data_out <= #TCQ (buf_err[0] ^ err) && err_valid;
	output_valid <= #TCQ err_valid;
end


endmodule
