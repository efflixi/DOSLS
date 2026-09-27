NASM ?= nasm
PYTHON ?= python3

.PHONY: all clean

all: LS.EXE

LS.BIN: ls.asm
	$(NASM) -f bin -Wall -o $@ $<

LS.EXE: LS.BIN build_mz.py
	$(PYTHON) build_mz.py $< $@

clean:
	rm -f LS.BIN LS.EXE
