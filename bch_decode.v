`timescale 1ns / 1ps

module bch_decode #(
	parameter N = 15,
	parameter K = 5,
	parameter T = 3,	/* Correctable errors */
	parameter OPTION = "SERIAL"
) (
	input clk,
	input reset,
	input din,
	output vdout,
	output dout
);

`include "bch.vh"

if (T < 3) begin
	dec_decode #(N, K, T) u_decode(
		.clk(clk),
		.reset(reset),
		.din(din),
		.vdout(vdout),
		.dout(dout)
	);
end else begin
	tmec_decode #(N, K, T, OPTION) u_decode(
		.clk(clk),
		.reset(reset),
		.din(din),
		.vdout(vdout),
		.dout(dout)
	);
end

endmodule
