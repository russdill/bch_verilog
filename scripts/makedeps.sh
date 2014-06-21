#!/bin/bash

target="$1"
shift
files="$@"
 
iverilog -E -tnull -M.$target.P $files
deps=$(cat .$target.P | sort -u)
rm .$target.P
(
	echo $target.ngc: $deps
	echo
	echo "$deps " | sed 's/$/:\n\n/g'
)
