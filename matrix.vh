/*
 * BCH Encode/Decoder Modules
 *
 * Copyright 2014 - Russ Dill <russ.dill@asu.edu>
 * Distributed under 2-clause BSD license as contained in COPYING file.
 */
 
function [R*C-1:0] rotate_matrix;
	input [C*R-1:0] in;
	integer i;
	integer j;
begin
	for (i = 0; i < R; i = i + 1)
		for (j = 0; j < C; j = j + 1)
			rotate_matrix[j*C+i] = in[i*C+j];
end
endfunction

function [C*R-1:0] expand_matrix;
	input [C+R-2:0] matrix;
	integer i;
begin
	for (i = 0; i < R; i = i + 1)
		expand_matrix[i*C+:C] = matrix[i+:C];
end
endfunction

