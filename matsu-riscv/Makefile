IVERILOG := iverilog
VVP := vvp

SRC_DIR := ./lab6
IV_FLAGS := -I $(SRC_DIR)  -g2012
TB_DIR := tb
SRC := $(wildcard $(SRC_DIR)/*.sv)
TB := $(wildcard $(TB_DIR)/*.sv)

OUT := sim.out
VCD := wave.vcd

all: $(OUT)

$(OUT): $(SRC)
	$(IVERILOG) $(IV_FLAGS) -o $@ $^

run: $(OUT)
	$(VVP) $<

wave: run
	gtkwave $(VCD)

clean:
	rm -f $(OUT) $(VCD)

.PHONY: all run clean wave
