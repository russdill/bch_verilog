`timescale 1ns / 1ps

module bch_syndrome #(
	parameter M = 4,
	parameter T = 3		/* Correctable errors */
) (
	input clk,
	input ce,
	input pe,
	input din,
	output [2*T*M-1:M] out
);

`include "bch.vh"
`include "bch_syndrome.vh"

localparam TCQ = 1;

genvar j;
genvar bit_pos;
genvar idx;
genvar syn_done;

localparam SYN_COUNT = syndrome_count(M, T);
reg [SYN_COUNT*M-1:0] syndromes = 0;
/*
wire [M-1:0] syn1 = syndromes[0*M+:M];
wire [M-1:0] syn3 = syndromes[1*M+:M];
wire [M-1:0] syn5 = syndromes[2*M+:M];

wire [M-1:0] dout1 = out[1*M+:M];
wire [M-1:0] dout2 = out[2*M+:M];
wire [M-1:0] dout3 = out[3*M+:M];
wire [M-1:0] dout4 = out[4*M+:M];
wire [M-1:0] dout5 = out[5*M+:M];
*/

/* LFSR registers */
generate
	for (idx = 0; idx < SYN_COUNT; idx = idx + 1) begin : syndrome_gen
		if (syndrome_method(M, T, idx2syn(M, idx)) == 0) begin
			/* First method */
			for (bit_pos = 0; bit_pos < M; bit_pos = bit_pos + 1) begin : first
				always @(posedge clk) begin
					if (pe)
						syndromes[idx*M+bit_pos] <= #TCQ bit_pos ? 1'b0 : din;
					else if (ce)
						syndromes[idx*M+bit_pos] <= #TCQ
							^(syndromes[idx*M+:M] & first_way_terms(M, idx2syn(M, idx), bit_pos)) ^
							(bit_pos ? 0 : din);
				end
			end
		end else begin
			/* Second method */
			always @(posedge clk) begin
				if (pe)
					syndromes[idx*M+:M] <= #TCQ {{M-1{1'b0}}, din};
				else if (ce)
					syndromes[idx*M+:M] <= #TCQ {syndromes[idx*M+:syndrome_size(M, idx2syn(M, idx))-1], din} ^
						(syndrome_poly(M, idx2syn(M, idx)) & {M{syndromes[idx*M+syndrome_size(M, idx2syn(M, idx))-1]}});
			end
		end
	end
endgenerate

/* Data output */
genvar dat;
for (dat = 1; dat < 2 * T; dat = dat + 1) begin : assign_dat
	if (syndrome_method(M, T, dat2syn(M, dat)) == 0)
		/* First method */
		assign out[dat*M+:M] = syndromes[dat2idx(M, dat)*M+:M];
	else begin
		/* Second method */
		for (bit_pos = 0; bit_pos < M; bit_pos = bit_pos + 1) begin : second
			assign out[dat*M+bit_pos] =
				^(syndromes[dat2idx(M, dat)*M+:M] & second_way_terms(M, dat, bit_pos));
		end
	end
end

endmodule
