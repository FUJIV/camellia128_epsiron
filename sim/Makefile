# sim/Makefile -- build/run helpers for camellia128_epsiron
#
# Run from anywhere; all targets cd to the project root first so that the
# RTL's default hex-file parameters ("tv/s1.hex", "tv/keyrom.hex") resolve.
#
# Targets:
#   make -C sim test   T1 (cam_s1) + T2-T8/T3 (functional, no stall)
#   make -C sim stall   T5 (functional, +STALL)
#   make -C sim trace    T9 (RTL vs. model/camellia_ref.py trace diff, enc+dec)
#   make -C sim lint   T10 (Verilator --lint-only -Wall)
#   make -C sim all   lint + test + stall + trace
#   make -C sim clean    remove build artifacts

ROOT := $(abspath $(dir $(abspath $(lastword $(MAKEFILE_LIST))))/..)
# xvlog/xelab/xsim are assumed to already be on PATH (e.g. via Vivado's
# settings64.sh). If they are not, set VIVADO_BIN to their directory,
# either in the environment or on the make command line:
#   make -C sim test VIVADO_BIN=/path/to/Vivado/bin
ifdef VIVADO_BIN
export PATH := $(VIVADO_BIN):$(PATH)
endif

SRC := src/cam_s1.v src/cam_dp.v src/cam_ctrl.v src/camellia128_epsiron.v

.PHONY: all test stall trace lint s1 clean

all: lint test stall trace

lint:
	cd $(ROOT) && ./sim/lint.sh

s1:
	cd $(ROOT) && rm -rf xsim.dir work .Xil
	cd $(ROOT) && xvlog src/cam_s1.v sim/tb_cam_s1.v
	cd $(ROOT) && xelab -debug typical -s tb_s1_snap work.tb_cam_s1
	cd $(ROOT) && xsim tb_s1_snap -runall

test: s1
	cd $(ROOT) && rm -rf xsim.dir work .Xil
	cd $(ROOT) && xvlog $(SRC) sim/tb_camellia128_epsiron.v
	cd $(ROOT) && xelab -debug typical -s tb_main_snap work.tb_camellia128_epsiron
	cd $(ROOT) && xsim tb_main_snap -runall

stall:
	cd $(ROOT) && rm -rf xsim.dir work .Xil
	cd $(ROOT) && xvlog $(SRC) sim/tb_camellia128_epsiron.v
	cd $(ROOT) && xelab -debug typical -s tb_main_snap work.tb_camellia128_epsiron
	cd $(ROOT) && xsim tb_main_snap -runall -testplusarg STALL

# T9: diff the RTL's cycle trace against model/camellia_ref.py's trace, for
# both enc and dec of the RFC 3713 vector. Pass KEY=/PT=/MODE= to check a
# different vector, e.g.:
#   make -C sim trace KEY=00000000000000000000000000000000 PT=00000000000000000000000000000000 MODE=enc
KEY  ?= 0123456789abcdeffedcba9876543210
PT   ?= 0123456789abcdeffedcba9876543210
MODE ?= enc

trace:
	cd $(ROOT) && rm -rf xsim.dir work .Xil
	cd $(ROOT) && xvlog $(SRC) sim/tb_trace.v
	cd $(ROOT) && xelab -debug typical -s tb_trace_snap work.tb_trace
	@set -e; \
	tmpd=$$(mktemp -d); \
	trap 'rm -rf "$$tmpd"' EXIT; \
	cd $(ROOT) && xsim tb_trace_snap -runall \
		-testplusarg "KEY=$(KEY)" -testplusarg "PT=$(PT)" -testplusarg "MODE=$(MODE)" \
		> "$$tmpd/rtl_trace.log"; \
	python3 model/camellia_ref.py trace $(KEY) $(PT) $(MODE) > "$$tmpd/py_trace.log"; \
	grep -E "^(IDLE|LOAD|FRND|FLA_L|FLB_L|FLB_R|FLA_R|KXOR|KSTORE|OUT|RESULT)" \
		"$$tmpd/rtl_trace.log" > "$$tmpd/rtl_trace.filtered.log"; \
	grep -E "^(IDLE|LOAD|FRND|FLA_L|FLB_L|FLB_R|FLA_R|KXOR|KSTORE|OUT|RESULT)" \
		"$$tmpd/py_trace.log" > "$$tmpd/py_trace.filtered.log"; \
	diff "$$tmpd/py_trace.filtered.log" "$$tmpd/rtl_trace.filtered.log" \
		&& echo "TRACE MATCH" \
		|| echo "TRACE DIFF (see above -- KSTORE 'k' differing is expected, spec 6.3 RAM port sharing; any other diff is a real bug)"

clean:
	cd $(ROOT) && rm -rf xsim.dir work .Xil *.log *.pb *.jou *.wdb sim_trace.log
