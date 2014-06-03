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

tb_sim: tb_sim.v sim.v bch_encode.v bch_decode.v tmec_decode.v tmec_decode_serial.v tmec_decode_parallel.v dec_decode.v bch_math.v tmec_decode_control.v bch_syndrome.v chien.v bch_syndrome_method1.v bch_syndrome_method2.v
	$(IVERILOG) $(VFLAGS) $^ -o $@ $(ON) $(OK) $(OT) $(OSEED) $(OOPTION)

clean:
	-rm -f $(BINS)
