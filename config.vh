`ifndef _CONFIG_VH_
`define _CONFIG_VH_

`define CONFIG_HAS_CARRY4 1
`define CONFIG_PIPELINE_LFSR 1
`define CONFIG_CONST_OP 1

`ifndef LUT_SZ
`define CONFIG_LUT_SZ 6
`endif

`ifndef LUT_MAX_SZ
`define CONFIG_LUT_MAX_SZ 8
`endif

`ifndef CONFIG_HAS_CARRY4
`define CONFIG_HAS_CARRY4 0
`endif

`ifndef CONFIG_PIPELINE_LFSR
`define CONFIG_PIPELINE_LFSR 0
`endif

`ifndef CONFIG_CONST_OP
`define CONFIG_CONST_OP 0
`endif

`endif
