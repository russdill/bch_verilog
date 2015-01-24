`include "bch_defs.vh"

module tb_basis_m();

	`include "bch.vh"

	parameter M = 8;
	integer i;
	reg [M-1:0] s;
	reg [M-1:0] s1;
	reg [M-1:0] d;
	integer error;
	initial begin
		s = `BCH_POLYNOMIAL(M);
		error = 0;
		for (i = 0; i < `BCH_M2N(M); i = i + 1) begin
			d = standard_to_dual(M, s);
			s1 = dual_to_standard(M, d);
			if (s1 != s) begin
				$display("Mismatch! %b/%b != %b", s, d, s1);
				error = 1;
			end
			s = `BCH_MUL1(M, s);
		end
		$display("%s (M = %d)", error ? "Failed" : "Success", M);
	end
endmodule

module tb_basis();
	genvar i;
	generate
	for (i = 2; i <= `MAX_M; i = i + 1) begin : FOO
		tb_basis_m #(i) test();
	end
	endgenerate
endmodule
