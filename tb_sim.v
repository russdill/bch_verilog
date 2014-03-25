`timescale 1ns / 1ps

module tb_sim();

parameter N = 31;
parameter K = 11;
parameter T = 5;
parameter ITERATIONS = 100;

localparam TCQ = 1;

reg clk = 0;
reg reset = 0;
reg [K-1:0] din = 0;
reg [$clog2(T+2)-1:0] nerr = 0;
reg [N-1:0] error = 0;
reg [$clog2(ITERATIONS+1)-1:0] iter = ITERATIONS;

function [K-1:0] randk;
	integer i;
begin
	for (i = 0; i < (31 + K) / 32; i = i + 1)
		if (i * 32 > K)
			randk[i*32+:K%32] = $random;
		else
			randk[i*32+:32] = $random;
end
endfunction

function integer n_errors;
	integer i;
begin
	n_errors = (32'h7fff_ffff & $random) % (T + 1);
end
endfunction

function [N-1:0] rande;
	input [31:0] nerr;
	integer i;
begin
	rande = 0;
	while (nerr) begin
		i = (32'h7fff_ffff & $random) % N;
		if (!((1 << i) & rande)) begin
			rande = rande | (1 << i);
			nerr = nerr - 1;
		end
	end
end
endfunction

wire vdin;
wire vdout;
wire wrongNow;
wire wrong;
wire [K-1:0] dout;

initial begin
	$dumpfile("test.vcd");
        $dumpvars(0);
end

sim #(N, K, T) u_sim(
	.clk(clk),
	.reset(reset),
	.din(din),
	.error(error),
	.vdin(vdin),
	.vdout(vdout),
	.wrongNow(wrongNow),
	.wrong(wrong),
	.dout(dout)
);

always
	#5 clk = ~clk;

always @(posedge wrong)
	$finish;

always @(negedge vdin) begin
	din <= randk();
	nerr <= n_errors();
	error <= rande(nerr);
	$display("%b %d flips - %b", din, nerr, error);
end

initial begin
	$display("(%1d, %1d, %1d)", N, K, T);
	@(posedge clk);
	@(posedge clk);
	reset <= #1 1;
	@(posedge clk);
	@(posedge clk);
	reset <= #1 0;
end

endmodule
