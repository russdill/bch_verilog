module xilinx_syndrome #(
	parameter T = 3,
	parameter DATA_BITS = 5,
	parameter BITS = 1,
	parameter REG_RATIO = 1,
	parameter PIPELINE_STAGES = 0
) (
	input [BITS-1:0] data_in,
	input clk_in,
	input start,
	input ce,
	output ready,
	output [BITS-1:0] data_out,
	output first,
	output last,
	output data_bits,
	output ecc_bits
);
	`include "bch_params.vh"
	localparam BCH_PARAMS = bch_params(DATA_BITS, T);

	wire [BITS-1:0] data_in0;
	wire start0;
	wire ce0;
	wire ready0;
	wire [BITS-1:0] data_out0;
	wire done0;

	BUFG u_bufg (
		.I(clk_in),
		.O(clk)
	);

	pipeline #(2) u_input [BITS+2-1:0] (
		.clk(clk),
		.i({data_in, start, ce}),
		.o({data_in0, start0, ce0})
	);

	pipeline #(2) u_output [BITS+2-1:0] (
		.clk(clk),
		.i({ready0, data_out0, done0}),
		.o({ready, data_out, done})
	);

	bch_syndrome #(BCH_PARAMS, BITS, REG_RATIO, PIPELINE_STAGES) u_bch_syndrome(
		.clk(clk),
		.start(start0),
		.ready(ready0),
		.ce(ce0),
		.data_in(data_in0),
		.syndromes(data_out0),
		.done(done0)
	);

endmodule

