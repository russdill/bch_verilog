
`include "bch_defs.vh"

module xilinx_error_dec #(
	parameter T = 2,
	parameter DATA_BITS = 5,
	parameter BITS = 1,
	parameter REG_RATIO = 1,
	parameter PIPELINE_STAGES = 0
) (
	input clk_in,
	input start,					/* Latch inputs, start calculating */
	input [`BCH_SYNDROMES_SZ(P)-1:0] syndromes,
	output [`BCH_ERR_SZ(P)-1:0] err_count,		/* Valid during valid cycles */
	output ready,
	output first,					/* First valid output data */
	output last,					/* Last valid output cycle */
	output valid,					/* Outputting data */
	output [BITS-1:0] err
);
	`include "bch_params.vh"
	localparam P = bch_params(DATA_BITS, T);

	wire clk;
	wire start0;
	wire [`BCH_SYNDROMES_SZ(P)-1:0] syndromes0;
	wire [`BCH_ERR_SZ(P)-1:0] err_count0;
	wire ready0;
	wire first0;
	wire last0;
	wire valid0;
	wire [BITS-1:0] err0;

	BUFG u_bufg (
		.I(clk_in),
		.O(clk)
	);

	pipeline #(2) u_input [`BCH_SYNDROMES_SZ(P)+1-1:0] (
		.clk(clk),
		.i({syndromes, start}),
		.o({syndromes0, start0})
	);

	pipeline #(2) u_output [`BCH_ERR_SZ(P)+BITS+4-1:0] (
		.clk(clk),
		.i({ready0, err_count0, first0, last0, valid0, err0}),
		.o({ready, err_count, first, last, valid, err})
	);

	bch_error_dec #(P, BITS, REG_RATIO, PIPELINE_STAGES) u_error_dec(
		.clk(clk),
		.start(start0),
		.ready(ready0),
		.syndromes(syndromes0),
		.first(first0),
		.last(last0),
		.valid(valid0),
		.err(err0),
		.err_count(err_count0)
	);


endmodule

