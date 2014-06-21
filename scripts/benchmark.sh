#!/bin/bash

prj="$1"
shift
configs=$(echo $@)

#echo -n > $prj.stats

for config in $configs; do
	_config=$(echo $config | sed 's/,/ /g')
	rm -f ${prj}_par.ptwx ${prj}_par.xrpt
	echo make -f Makefile.xilinx ${prj}_par.ncd GENERICS="$_config"
	make -f Makefile.xilinx ${prj}_par.ncd GENERICS="$_config" || continue
	slices=$(xmllint --xpath '//document/application[last()]/task[@stringID="PAR_DEVICE_UTLIZATION"]/section[@stringID="PAR_SLICE_REPORTING"]/item[@stringID="PAR_OCCUPIED_SLICES"]/@value' ${prj}_par.xrpt | cut -f 2 -d '"')
	ns=$(xmllint --xpath '//twReport/twBody/twSumRpt/twConstSummaryTable/twConstSummary/twConstData/@best' ${prj}_par.ptwx | cut -f 2 -d '"')
	mhz=$(echo "scale=1; 1000/$ns;" | bc)
	echo $config $slices $mhz >> $prj.stats
done




