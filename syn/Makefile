# syn/Makefile -- OOC synthesis / size evaluation (T11)
#
#   make -C syn        run Vivado OOC synthesis, write reports to syn/run/
#   make -C syn clean  remove the (gitignored) run directory

ROOT := $(abspath $(dir $(abspath $(lastword $(MAKEFILE_LIST))))/..)
# vivado is assumed to already be on PATH (e.g. via Vivado's settings64.sh).
# If it is not, set VIVADO_BIN to its directory, either in the environment
# or on the make command line:
#   make -C syn VIVADO_BIN=/path/to/Vivado/bin
ifdef VIVADO_BIN
export PATH := $(VIVADO_BIN):$(PATH)
endif

.PHONY: all clean

all:
	cd $(ROOT) && vivado -mode batch -nojournal -nolog -source syn/ooc_synth.tcl

clean:
	cd $(ROOT) && rm -rf syn/run *.jou *.log .Xil
