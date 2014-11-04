#!/bin/bash

scripts/benchmark.sh xilinx_error_tmec "PIPELINE_STAGES={0,1,2},DATA_BITS={64,256,4096},T={3,8,12},BITS={1,8,16},REG_RATIO={1,4,8}"

