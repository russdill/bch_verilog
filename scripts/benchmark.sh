#!/bin/bash

prj="$1"
shift
echo $1
if [ -n "$1" ]; then
	configs=$(eval echo $1)
else
	configs=""
fi
if [ -n "$2" ]; then
	defines=$(eval echo $2)
else
	defines="\"\""
fi

#echo -n > $prj.stats
for config in $configs; do
	_config=$(echo $config | sed 's/,/ /g')
	for define in $defines; do
		_define=$(echo $define | sed 's/,/ /g')
		echo make -f Makefile.xilinx ${prj}_par.ncd GENERICS="$_config" DEFINES="$_define"
		echo $config $define >> $prj.times
		/usr/bin/time -a -o $prj.times make -f Makefile.xilinx ${prj}_par.ncd GENERICS="$_config" DEFINES="$_define" || continue
		slices=$(xmllint --xpath '//document/application[last()]/task[@stringID="PAR_DEVICE_UTLIZATION"]/section[@stringID="PAR_SLICE_REPORTING"]/item[@stringID="PAR_OCCUPIED_SLICES"]/@value' ${prj}_par.xrpt | cut -f 2 -d '"')
		ns=$(xmllint --xpath '//twReport/twBody/twSumRpt/twConstSummaryTable/twConstSummary/twConstData/@best' ${prj}_par.ptwx | cut -f 2 -d '"')
		mhz=$(echo "scale=1; 1000/$ns;" | bc)
		echo $config $define $slices $mhz >> $prj.stats
	done
done




