SIM_DIR=$(HOME)/opt/Xilinx/current/ISE_DS/ISE/verilog/src
IVERILOG=iverilog

BINS=tb_sim tb_basis tb_mult
VFLAGS=-g2005-sv -Wall -y$(SIM_DIR)/unisims

ifdef DATA_BITS
ODATA_BITS = -Ptb_sim.DATA_BITS=$(DATA_BITS)
endif

ifdef BITS
OBITS = -Ptb_sim.BITS=$(BITS)
endif

ifdef T
OT = -Ptb_sim.T=$(T)
endif

ifdef SEED
OSEED = -Ptb_sim.SEED=$(SEED)
endif

ifdef OPTION
OOPTION = -Ptb_sim.OPTION=\"$(OPTION)\"
endif

ifdef REG_RATIO
OREG_RATIO = -Ptb_sim.REG_RATIO=$(REG_RATIO)
endif

all: tb_sim
V=\
bch_chien.v \
bch_encode.v \
bch_blank_ecc.v \
bch_error_dec.v \
bch_error_tmec.v \
bch_error_one.v \
bch_math.v \
bch_sigma_bma_parallel.v \
bch_sigma_bma_serial.v \
bch_sigma_bma_noinv.v \
bch_syndrome_method1.v \
bch_syndrome_method2.v \
bch_syndrome.v \
compare_cla.v \
sim.v \
util.v \
matrix.v \
tb_sim.v

tb_sim: $(V)
	$(IVERILOG) $(VFLAGS) $^ -o $@ $(ODATA_BITS) $(OBITS) $(OT) $(OSEED) $(OOPTION) $(OREG_RATIO)

tb_basis: tb_basis.v
	$(IVERILOG) $(VFLAGS) $^ -o $@

tb_mult: tb_mult.v bch_math.v matrix.v
	$(IVERILOG) $(VFLAGS) $^ -o $@

tb_inverter: tb_inverter.v bch_math.v matrix.v
	$(IVERILOG) $(VFLAGS) $^ -o $@

bch_decoder: bch_decoder.v bch_chien.v bch_error_tmec.v bch_error_one.v \
	 bch_math.v bch_sigma_bma_serial.v bch_syndrome_method1.v \
	 bch_syndrome_method2.v bch_syndrome.v compare_cla.v util.v matrix.v
	 $(IVERILOG) $(VFLAGS) $^ -o $@

clean:
	-rm -f $(BINS)
