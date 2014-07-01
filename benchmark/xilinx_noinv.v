
`include "bch_defs.vh"

module xilinx_noinv #(
	parameter T = 3,
	parameter DATA_BITS = 5
) (
	input clk_in,
	input in,
	output reg out = 0
);
	`include "bch_params.vh"
	localparam P = bch_params(DATA_BITS, T);
	localparam IN = `BCH_SYNDROMES_SZ(P) + 2;
	localparam OUT = `BCH_SIGMA_SZ(P) + `BCH_ERR_SZ(P) + 2;

	wire start;
	wire [`BCH_SYNDROMES_SZ(P)-1:0] syndromes;
	wire ack_done;
	wire done;
	wire ready;
	wire [`BCH_SIGMA_SZ(P)-1:0] sigma;
	wire [`BCH_ERR_SZ(P)-1:0] err_count;

	(* KEEP = "TRUE" *)
	reg [IN-1:0] all;

	(* KEEP = "TRUE" *)
	reg [OUT-1:0] out_all;

	(* KEEP = "TRUE" *)
	reg in1, in2, out1;
	wire out2;
	
	BUFG u_bufg (
		.I(clk_in),
		.O(clk)
	);

	assign start = all[0];
	assign ack_done = all[1];
	assign syndromes = all >> 2;
	assign out2 = out_all[0];

	always @(posedge clk) begin

		in1 <= in;
		in2 <= in1;
		out <= out1;
		out1 <= out2;

		all <= (all << 1) | in2;
		if (done)
			out_all <= {done, ready, sigma, err_count};
		else
			out_all <= out_all >> 1;
	end
		
	bch_sigma_bma_noinv #(P) u_bma (
		.clk(clk),
		.start(start),
		.ready(ready),
		.syndromes(syndromes),
		.sigma(sigma),
		.done(done),
		.ack_done(ack_done),
		.err_count(err_count)
	);



endmodule

