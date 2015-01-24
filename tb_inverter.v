`timescale 1ns / 1ps

module tb_inverter();
	`include "bch.vh"

	localparam M = 8;

	reg clk = 0;
	reg start = 1;
	reg in = 0;
	wire [M-1:0] out;
	reg [M-1:0] out2 = 0;
	wire [M-1:0] out_dual;
	reg [M-1:0] v = 0;
	integer i;
	reg [M-1:0] a;
	reg [M-1:0] b;

	berlekamp_inverter #(M) inv(
		.clk(clk),
		.start(start),
		.standard_in(in),
		.standard_out(out)
	);

	fermat_inverter #(M) inv2(
		.clk(clk),
		.start(start),
		.standard_in(a),
		.dual_out(out_dual)
	);

	initial begin
		$dumpfile("test.vcd");
		$dumpvars(0);
		a = lpow(M, 0);
		#1;
		for (i = 0; i < `BCH_M2N(M); i = i + 1) begin
			b = brute_inverse(M, a);
			v = a << 1;
			in = a[M-1];
			start = 1;
			#4;
			clk = 1;
			#1;
			repeat (M) begin
				in = v[M-1];
				v = v << 1;
				start = 0;
				#4;
				clk = 0;
				#5;
				clk = 1;
				#1;
			end
			out2 = dual_to_standard(M, out_dual);
			repeat (M - 2) begin
				in = 0;
				#4;
				clk = 0;
				#5;
				clk = 1;
				#1;
			end
			#4;
			clk = 0;
			#1;
			$display("%d 1/%b = %b, %b%s %b%s", i, a, b,
					out, b == out ? "" : "*",
					out2, b == out2 ? "" : "*");
			a = `BCH_MUL1(M, a);
		end
	end

endmodule
