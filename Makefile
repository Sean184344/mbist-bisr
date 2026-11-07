.PHONY: verify campaign formal mutations lint formal-port verilator demo package test matrix waves synth cocotb clean
.DEFAULT_GOAL := test
package: verify
	python3 scripts/package.py
demo:
	python3 examples/run_demo.py --latency 0 --waves
	python3 examples/run_demo.py --latency 1 --waves
verify:
	python3 tests/run_verification.py
	python3 scripts/export_results.py
campaign:
	python3 tests/run_campaign.py
formal:
	python3 tests/run_formal.py
formal-port:
	python3 tests/run_port_formal.py
verilator:
	python3 tests/run_verilator.py
lint:
	python3 tests/run_lint.py
mutations:
	python3 tests/run_mutations.py
test: build/sim
	python3 tests/run_matrix.py
	vvp build/sim
matrix:
	python3 tests/run_matrix.py
build/sim: rtl/mbist_bisr.v tests/tb.v
	mkdir -p build
	iverilog -g2012 -Wall -s tb -o $@ $^
waves: build/sim
	vvp build/sim +waves
	gtkwave build/mbist.vcd
synth:
	mkdir -p build
	yosys -Q -p 'read_verilog -sv rtl/mbist_bisr.v; hierarchy -check -top mbist_bisr; proc; opt; check -assert; synth -top mbist_bisr; check -assert; stat' > build/synthesis.log
	yosys -Q -p 'read_verilog -sv rtl/mbist_bisr.v rtl/mbist_subsystem.v; hierarchy -check -top mbist_subsystem; synth -top mbist_subsystem; check -assert; stat' > build/subsystem_synthesis.log
	yosys -Q -p 'read_verilog -sv rtl/mbist_bisr.v rtl/mbist_subsystem.v; chparam -set READ_LATENCY 1 mbist_subsystem; hierarchy -check -top mbist_subsystem; synth -top mbist_subsystem; check -assert; stat' > build/subsystem_sync_synthesis.log
	yosys -Q -p 'read_verilog -sv rtl/mbist_ram.v; hierarchy -check -top mbist_ram; synth -top mbist_ram; check -assert; stat' > build/ram_synthesis.log
	yosys -Q -p 'read_verilog -sv rtl/*.v; hierarchy -check -top mbist_memory; synth -top mbist_memory; check -assert; stat' > build/memory_sync_synthesis.log
	yosys -Q -p 'read_verilog -sv rtl/*.v; chparam -set READ_LATENCY 0 mbist_memory; hierarchy -check -top mbist_memory; synth -top mbist_memory; check -assert; stat' > build/memory_async_synthesis.log
cocotb:
	mkdir -p build
	$(MAKE) -f tests/cocotb.mk READ_LATENCY=0
	$(MAKE) -f tests/cocotb.mk READ_LATENCY=1
clean:
	rm -rf build sim_build results.xml
