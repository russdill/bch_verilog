`timescale 1ns / 1ps

/* Chien search, determines roots of a polynomial defined over a finite field */

module chien_reg #(
	parameter M = 4,
	parameter P = 1
) (
	input clk,
	input err,		/* Error was found so correct it */
	input ce,
	input start,
	input [M-1:0] in,
	output reg [M-1:0] out = 0
);
	`include "bch.vh"

	localparam TCQ = 1;
	localparam LPOW = lpow(M, P);

	wire [M-1:0] mul_out;

	parallel_standard_multiplier #(M) u_mult(
		.standard_in1(LPOW[M-1:0]),
		.standard_in2(out ^ err),
		.standard_out(mul_out)
	);

	always @(posedge clk)
		if (start)
			/* Initialize with coefficients of the error location polynomial */
			out <= #TCQ in;
		else if (ce)
			/* Multiply by alpha^P */
			out <= #TCQ mul_out;
endmodule

/*
 * SEC sigma(x) = 1 + S_1 * x
 * No error if S_1 = 0
 */
module chien_sec #(
	parameter M = 4,
	parameter T = 3
) (
	input start,
	input first_cycle,
	input [M*(T+1)-1:0] z,
	output err,
	output err_feedback
);
	assign err = z[0+:M] == 1;
	assign err_feedback = err;
endmodule

/*
 * DEC simga(x) = 1 + sigma_1 * x + sigma_2 * x^2 =
 *		1 + S_1 * x + (S_1^2 + S_3 * S_1^-1) * x^2
 * No  error  if S_1  = 0, S_3  = 0
 * one error  if S_1 != 0, S_3  = S_1^3
 * two errors if S_1 != 0, S_3 != S_1^3
 * >2  errors if S_1  = 0, S_3 != 0
 * The below may be a better choice for large circuits (cycles tradeoff)
 * sigma_1(x) = S_1 + S_1^2 * x + (S_1^3 + S_3) * x^2
 */
module chien_dec #(
	parameter M = 4,
	parameter T = 3
) (
	input start,
	input first_cycle,
	input [M*(T+1)-1:0] z,
	output err,
	output err_feedback
);
	wire [M-1:0] ch1_flipped;
	wire [M-1:0] ch3_flipped;

	wire [M-1:0] power;
	reg [1:0] errors_last = 0;
	wire [1:0] errors;

	/* For each cycle, try flipping the bit */
	assign ch1_flipped = z[M*0+:M] ^ !first_cycle;
	assign ch3_flipped = z[M*2+:M] ^ !first_cycle;

	pow3 #(M) u_pow3(
		.in(ch1_flipped),
		.out(power)
	);

	/* Calculate the number of erros */
	assign errors = |ch1_flipped ?
		(power == ch3_flipped ? 1 : 2) :
		(|ch3_flipped ? 3 : 0);
	/*
	 * If flipping reduced the number of errors,
	 * then we found an error
	 */
	assign err = errors_last > errors;
	assign err_feedback = err;

	always @(posedge clk)
		/*
		 * Load the new error count on cycle zero or when
		 * we find an error
		 */
		if (start)
			errors_last <= #TCQ 0;
		else if (first_cycle || err)
			errors_last <= #TCQ errors;

endmodule

/*
 * Tradition chien search, for each cycle, check if the
 * sum of all the equations is zero, if so, this location
 * is a bit error.
 */
module chien_tmec #(
	parameter M = 4,
	parameter T = 3
) (
	input start,
	input first_cycle,
	input [M*(T+1)-1:0] z,
	output err,
	output err_feedback
);
	wire [M-1:0] eq;

	finite_parallel_adder #(M, T+1) u_dcheq(z, eq);

	assign err = !eq;
	assign err_feedback = 0;
endmodule


/*
 * Each register is loaded with the associated syndrome
 * and multiplied by alpha^i each cycle.
 */
module bch_error #(
	parameter M = 4,
	parameter K = 5,
	parameter T = 3
) (
	input clk,
	input start,			/* Latch inputs, start calculating */
	input [M*(T+1)-1:0] sigma,
	output reg ready = 0,		/* First valid output data */
	output reg valid = 0,		/* Outputting data */
	output err
);
	wire [M*(T+1)-1:0] z;
	wire [M-1:0] count;
	reg first_cycle = 0;
	wire err_feedback;
	
	localparam TCQ = 1;
	localparam DONE = lfsr_count(M, K-2);

	lfsr_counter #(M) u_counter(
		.clk(clk),
		.reset(first_cycle),
		.ce(valid),
		.count(count)
	);

	always @(posedge clk) begin
		first_cycle <= #TCQ start;
		valid <= #TCQ first_cycle || (valid && count != DONE);
		ready <= #TCQ first_cycle;
	end

	genvar i;
	generate
	for (i = 0; i <= T; i = i + 1) begin : DCH
		chien_reg #(M, i + 1) u_ch(
			.clk(clk),
			.err(err_feedback),
			.ce(valid || first_cycle),
			.start(start),
			.in(sigma[i*M+:M]),
			.out(z[i*M+:M])
		);
	end
	endgenerate

	if (T == 1) begin : SEC
		chien_sec #(M, T) u_chien_sec(
			.start(start),
			.first_cycle(first_cycle),
			.z(z),
			.err(err),
			.err_feedback(err_feedback)
		);
	end else if (T == 2) begin : DEC
		chien_dec #(M, T) u_chien_dec(
			.start(start),
			.first_cycle(first_cycle),
			.z(z),
			.err(err),
			.err_feedback(err_feedback)
		);
	end else begin : TMEC
		chien_tmec #(M, T) u_chien_tmec(
			.start(start),
			.first_cycle(first_cycle),
			.z(z),
			.err(err),
			.err_feedback(err_feedback)
		);
	end
endmodule
