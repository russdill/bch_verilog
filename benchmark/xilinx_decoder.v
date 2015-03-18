module xilinx_decoder #(
	parameter T = 3,
	parameter DATA_BITS = 5,
	parameter BITS = 1,
	parameter SYN_REG_RATIO = 1,
	parameter ERR_REG_RATIO = 1,
	parameter SYN_PIPELINE_STAGES = 0,
	parameter ERR_PIPELINE_STAGES = 0,
	parameter ACCUM = 1
) (
	input [BITS-1:0] data_in,
	input clk_in,
	input start_in,
	output [BITS-1:0] err_out,
	output first_out
);
	`include "bch_params.vh"
	localparam BCH_PARAMS = bch_params(DATA_BITS, T);

	wire [`BCH_SYNDROMES_SZ(BCH_PARAMS)-1:0] syndromes;
	wire syn_done;
	wire key_ready;
	wire key_done;
	(* KEEP = "TRUE" *)
	(* S = "TRUE" *)
	wire [`BCH_SIGMA_SZ(BCH_PARAMS)-1:0] sigma;
	wire [`BCH_ERR_SZ(BCH_PARAMS)-1:0] err_count;
	wire err_first;
	wire [BITS-1:0] data;
	wire start;
	wire [BITS-1:0] err;

	pipeline #(1) u_pipeline [BITS*2+2-1:0] (
		.clk(clk),
		.i({data_in, start_in, err_first, err}),
		.o({data, start, first_out, err_out})
	);

	BUFG u_bufg (
		.I(clk_in),
		.O(clk)
	);

	bch_syndrome #(BCH_PARAMS, BITS, SYN_REG_RATIO, SYN_PIPELINE_STAGES) u_bch_syndrome(
		.clk(clk),
		.start(start),
		.ce(1'b1),
		.data_in(data),
		.syndromes(syndromes),
		.done(syn_done)
	);

	bch_sigma_bma_serial #(BCH_PARAMS) u_bma (
		.clk(clk),
		.start(syn_done && key_ready),
		.ready(key_ready),
		.syndromes(syndromes),
		.sigma(sigma),
		.done(key_done),
		.ack_done(1'b1),
		.err_count(err_count)
	);

	bch_error_tmec #(BCH_PARAMS, BITS, ERR_REG_RATIO, ERR_PIPELINE_STAGES, ACCUM) u_error_tmec(
		.clk(clk),
		.start(key_done),
		.sigma(sigma),
		.first(err_first),
		.err(err)
	);

endmodule

