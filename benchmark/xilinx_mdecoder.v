module xilinx_mdecoder #(
	parameter T = 3,
	parameter DATA_BITS = 64,
	parameter BITS = 4,
	parameter SYN_REG_RATIO = 1,
	parameter ERR_REG_RATIO = 1,
	parameter SYN_PIPELINE_STAGES = 0,
	parameter ERR_PIPELINE_STAGES = 0,
	parameter ACCUM = 1,
	parameter NCHANNEL = 4,
	parameter NKEY = 2,
	parameter NCHIEN = 1
) (
	input [NCHANNEL*BITS-1:0] data_in,
	input [NCHANNEL-1:0] start_in,
	output [NCHANNEL-1:0] ready_out,
	input clk_in,
	output [NCHANNEL*BITS-1:0] err_out,
	output [NCHANNEL-1:0] first_out
);
	`include "bch_params.vh"

	wire clk;
	wire [NCHANNEL*BITS-1:0] data;
	wire [NCHANNEL-1:0] start;
	wire [NCHANNEL-1:0] ready;
	wire [NCHANNEL*BITS-1:0] err;
	wire [NCHANNEL-1:0] first;

	pipeline #(1) u_pipeline [NCHANNEL*(BITS*2+3)-1:0] (
		.clk(clk),
		.i({data_in, start_in, ready, first, err}),
		.o({data, start, ready_out, first_out, err_out})
	);

	BUFG u_bufg (
		.I(clk_in),
		.O(clk)
	);

	bch_decoder #(T, DATA_BITS, BITS, SYN_REG_RATIO, ERR_REG_RATIO,
			SYN_PIPELINE_STAGES, ERR_PIPELINE_STAGES,
			ACCUM, NCHANNEL, NKEY, NCHIEN) u_bch_decoder(
		.clk(clk),
		.data(data),
		.syn_start(start),
		.syn_ready(ready),
		.first_out(first),
		.err_out(err)
	);

endmodule

