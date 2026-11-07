SIM ?= icarus
READ_LATENCY ?= 0
TOPLEVEL_LANG = verilog
VERILOG_SOURCES = $(CURDIR)/rtl/mbist_bisr.v $(CURDIR)/rtl/mbist_subsystem.v $(CURDIR)/tests/cocotb_top.v
COMPILE_ARGS += -g2012 -Pcocotb_top.READ_LATENCY=$(READ_LATENCY)
TOPLEVEL = cocotb_top
COCOTB_TEST_MODULES = test_mbist
SIM_BUILD = sim_build/cocotb_$(READ_LATENCY)
COCOTB_RESULTS_FILE = build/cocotb_$(READ_LATENCY).xml
export READ_LATENCY
export PYTHONPATH := $(CURDIR)/tests:$(PYTHONPATH)
COCOTB_MAKEFILES := $(shell cocotb-config --makefiles 2>/dev/null)
ifeq ($(strip $(COCOTB_MAKEFILES)),)
$(error Cocotb is unavailable: activate .venv and run python -m pip install -r requirements.txt)
endif
include $(COCOTB_MAKEFILES)/Makefile.sim
