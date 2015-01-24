`timescale 1ns / 1ps

`include "bch_defs.vh"

module tb_mult_m();

	`include "bch.vh"

	parameter M = 8;
	integer i;
	integer j;
	reg [M-1:0] s1 = 0;
	reg [M-1:0] s2 = 0;
	reg [M-1:0] p1 = 0;
	reg [M-1:0] pd = 0;
	reg [M-1:0] p2d = 0;
	reg [M-1:0] p2 = 0;
	wire smm_out;
	wire smm_out1;
	reg serial_s2 = 0;
	wire [M-1:0] ssm_out;
	wire [M-1:0] pmm_out;
	reg [M-1:0] pmm_out_s;
	wire [M-1:0] psm_out;
	reg [M-1:0] smm_reg;
	reg [M-1:0] smm_reg1;
	reg [M-1:0] d = 0;
	reg start = 0;
	reg clk = 0;
	integer error;

	serial_mixed_multiplier #(M) smm(
		.clk(clk),
		.start(start),
		.dual_in(d),
		.standard_in(s2),
		.dual_out(smm_out)
	);

	serial_mixed_multiplier_dss #(M) smm1(
		.clk(clk),
		.start(start),
		.dual_in(d),
		.standard_in(s2),
		.standard_out(smm_out1)
	);

	parallel_mixed_multiplier #(M) pmm(
		.dual_in(d),
		.standard_in(s2),
		.dual_out(pmm_out)
	);

	parallel_standard_multiplier #(M) psm(
		.standard_in1(s1),
		.standard_in2(s2),
		.standard_out(psm_out)
	);

	serial_standard_multiplier #(M) ssm(
		.clk(clk),
		.reset(start),
		.ce(1'b1),
		.parallel_in(s1),
		.serial_in(serial_s2),
		.out(ssm_out)
	);

	initial begin
		//$dumpfile("test.vcd");
		//$dumpvars(0);
		error = 0;
		#5;
		clk = 1;
		for (i = 0; i < 5000; i = i + 1) begin
			s1 = $random;
			if (s1 == 0)
				s1 = s1 + 1;
			s2 = $random;
			if (s2 == 0)
				s2 = s2 + 1;
			d = standard_to_dual(M, s1);

			p1 = finite_mult(M, s1, s2);

			p2d = fixed_mixed_multiplier(M, d, s2);
			p2 = dual_to_standard(M, p2d);

			#1;

			if (p1 != p2) begin
				$display("Mismatch! %b * %b = %b != %b", s1, s2, p1, p2);
				error = 1;
			end

			if (p2d != pmm_out) begin
				$display("Mismatch! %b * %b = %b != %b", s1, s2, p2d, pmm_out);
				error = 1;
			end

			if (p1 != psm_out) begin
				$display("Mismatch! %b * %b = %b != %b", s1, s2, p1, psm_out);
				error = 1;
			end

			#1;
			start = 1;
			#4;
			clk = 0;
			#5;
			clk = 1;
			for (j = 0; j < M; j = j + 1) begin
				#1;
				start = 0;
				#1;
				smm_reg[j] = smm_out;
				smm_reg1[M - j - 1] = smm_out1;
				smm_reg2[M - j - 1] = smm_out2; 
				serial_s2 = s2[M - j - 1];
				#3; clk = 0;
				#4; clk = 1;
			end
			#4; clk = 0;
			#4; clk = 1;

			if (p1 != ssm_out) begin
				$display("SSM Mismatch! %b * %b = %b != %b", s1, s2, p1, ssm_out);
				error = 1;
			end

			if (p2d != smm_reg) begin
				$display("SMM Mismatch! %b * %b = %b != %b", s1, s2, p2d, smm_reg);
				error = 1;
			end

			if (p1 != smm_reg1) begin
				$display("SMM1 Mismatch! %b * %b = %b != %b", s1, s2, p1, smm_reg1);
				error = 1;
			end


		end
		$display("%s (M = %d)", error ? "Failed" : "Success", M);
	end

	
endmodule

module tb_mult();
//	tb_mult_m #(8) test();

	genvar i;
	generate
	for (i = 2; i <= `MAX_M; i = i + 1) begin : FOO
		tb_mult_m #(i) test();
	end
	endgenerate

endmodule
