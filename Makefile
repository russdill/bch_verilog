IVERILOG=iverilog

BINS=tb_sim
VFLAGS=-g2005-sv -Wall

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
OREG_RATIO = -Ptb_sim.REG_RATIO=\"$(REG_RATIO)\"
endif

all: $(BINS)
V=\
bch_chien.v \
bch_encode.v \
bch_error_dec.v \
bch_error_tmec.v \
bch_math.v \
bch_sigma_bma_parallel.v \
bch_sigma_bma_serial.v \
bch_syndrome_method1.v \
bch_syndrome_method2.v \
bch_syndrome.v \
sim.v \
util.v \
tb_sim.v

tb_sim: $(V)
	$(IVERILOG) $(VFLAGS) $^ -o $@ $(ODATA_BITS) $(OBITS) $(OT) $(OSEED) $(OOPTION) $(OREG_RATIO)

clean:
	-rm -f $(BINS)
