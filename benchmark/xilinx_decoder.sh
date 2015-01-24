#!/bin/bash

scripts/benchmark.sh xilinx_decoder "SYN_PIPELINE_STAGES=1,ERR_PIPELINE_STAGES=1,DATA_BITS={64,256},T={3,8},BITS={4,8},SYN_REG_RATIO=4,ERR_REG_RATIO=4"

