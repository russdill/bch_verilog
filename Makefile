IVERILOG=iverilog

BINS=tb_sim
VFLAGS=-g2005-sv -Wall

ifdef N
ON = -Ptb_sim.N=$(N)
endif

ifdef K
OK = -Ptb_sim.K=$(K)
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

all: $(BINS)
V=\
bch_encode.v \
bch_error.v \
bch_key.v \
bch_math.v \
bch_syndrome_method1.v \
bch_syndrome_method2.v \
bch_syndrome.v \
bma_parallel.v \
bma_serial.v \
sim.v \
tb_sim.v

tb_sim: $(V)
	$(IVERILOG) $(VFLAGS) $^ -o $@ $(ON) $(OK) $(OT) $(OSEED) $(OOPTION)

clean:
	-rm -f $(BINS)
