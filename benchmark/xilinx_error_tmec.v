
`include "bch_defs.vh"

module xilinx_error_tmec #(
	parameter T = 2,
	parameter DATA_BITS = 5,
	parameter BITS = 1,
	parameter REG_RATIO = 1,
	parameter PIPELINE_STAGES = 0
) (
	input clk_in,
	input start,			/* Latch inputs, start calculating */
	input [`BCH_SIGMA_SZ(P)-1:0] sigma,
	output ready,
	output first,			/* First valid output data */
	output last,
	output valid,			/* Outputting data */
	output [BITS-1:0] err
);
	`include "bch_params.vh"
	localparam P = bch_params(DATA_BITS, T);

	wire clk;
	wire start0;
	wire [`BCH_SIGMA_SZ(P)-1:0] sigma0;
	wire ready0;
	wire first0;
	wire last0;
	wire valid0;
	wire [BITS-1:0] err0;

	BUFG u_bufg (
		.I(clk_in),
		.O(clk)
	);

	pipeline #(2) u_input [`BCH_SIGMA_SZ(P)+1-1:0] (
		.clk(clk),
		.i({sigma, start}),
		.o({sigma0, start0})
	);

	pipeline #(2) u_output [BITS+4-1:0] (
		.clk(clk),
		.i({ready0, first0, last0, valid0, err0}),
		.o({ready, first, last, valid, err})
	);

	bch_error_tmec #(P, BITS, REG_RATIO, PIPELINE_STAGES) u_error_tmec(
		.clk(clk),
		.start(start0),
		.ready(ready0),
		.sigma(sigma0),
		.first(first0),
		.last(last0),
		.valid(valid0),
		.err(err0)
	);


endmodule

