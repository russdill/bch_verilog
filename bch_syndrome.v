`timescale 1ns / 1ps

module bch_syndrome #(
	parameter M = 4,
	parameter T = 3		/* Correctable errors */
) (
	input clk,
	input ce,
	input pe,
	input snce,
	input din,
	output [2*T*M-1:M] out,
	output reg [(2*T-1)*M-1:0] snNout = 0
);

`include "bch.vh"
`include "bch_syndrome.vh"

localparam TCQ = 1;

genvar i;
genvar j;
genvar bit_pos;
genvar idx;
genvar syn_done;

localparam SYN_COUNT = syndrome_count(M, T);
reg [SYN_COUNT*M-1:0] syndromes = 0;

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


/* Syndrome shuffling */
/* snN drdce */
generate
	for (i = 0; i < 2*T-1; i = i + 1) begin : s
		if (i == T + 1 && T < 4) begin
			always @(posedge clk)
				if (pe)
					snNout[i*M+:M] <= #TCQ out[(3*T-i-1)*M+:M];
		end else begin
			always @(posedge clk)
				if (snce)				/* xN dmul21 */
					snNout[i*M+:M] <= #TCQ pe ? out[M*((2*T+1-i)%(2*T-1)+1)+:M] : snNout[M*((i+(2*T-3))%(2*T-1))+:M];
		end
	end
endgenerate


endmodule
