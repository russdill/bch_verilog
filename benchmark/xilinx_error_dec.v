
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
	output first,					/* First valid output data */
	output [BITS-1:0] err
);
	`include "bch_params.vh"
	localparam P = bch_params(DATA_BITS, T);

	wire clk;
	wire start0;
	wire [`BCH_SYNDROMES_SZ(P)-1:0] syndromes0;
	wire [`BCH_ERR_SZ(P)-1:0] err_count0;
	wire first0;
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

	pipeline #(2) u_output [`BCH_ERR_SZ(P)+BITS+3-1:0] (
		.clk(clk),
		.i({err_count0, first0, err0}),
		.o({err_count, first, err})
	);

	bch_error_dec #(P, BITS, REG_RATIO, PIPELINE_STAGES) u_error_dec(
		.clk(clk),
		.start(start0),
		.syndromes(syndromes0),
		.first(first0),
		.err(err0),
		.err_count(err_count0)
	);


endmodule

