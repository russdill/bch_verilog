
`include "bch_defs.vh"

module xilinx_serial #(
	parameter T = 3,
	parameter DATA_BITS = 5
) (
	input clk_in,
	input start,
	input [`BCH_SYNDROMES_SZ(P)-1:0] syndromes,
	input ack_done,

	output done,
	output ready,
	output [`BCH_SIGMA_SZ(P)-1:0] sigma,
	output [`BCH_ERR_SZ(P)-1:0] err_count
);
	`include "bch_params.vh"
	localparam P = bch_params(DATA_BITS, T);

	wire [`BCH_SYNDROMES_SZ(P)-1:0] syndromes0;
	wire start0;
	wire ce0;
	wire ready0;
	wire [`BCH_SIGMA_SZ(P)-1:0] sigma0;
	wire [`BCH_ERR_SZ(P)-1:0] err_count0;
	wire done0;
	wire ack_done0;

	BUFG u_bufg (
		.I(clk_in),
		.O(clk)
	);

	pipeline #(2) u_input [`BCH_SYNDROMES_SZ(P)+2-1:0] (
		.clk(clk),
		.i({syndromes, start, ack_done}),
		.o({syndromes0, start0, ack_done0})
	);

	pipeline #(2) u_output [`BCH_SIGMA_SZ(P)+`BCH_ERR_SZ(P)+2-1:0] (
		.clk(clk),
		.i({ready0, sigma0, done0, err_count0}),
		.o({ready, sigma, done, err_count})
	);

	bch_sigma_bma_serial #(P) u_bma (
		.clk(clk),
		.start(start0),
		.ready(ready0),
		.syndromes(syndromes0),
		.sigma(sigma0),
		.done(done0),
		.ack_done(ack_done0),
		.err_count(err_count0)
	);



endmodule

