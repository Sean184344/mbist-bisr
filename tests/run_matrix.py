"""Run actual RTL simulations across boundary and representative parameters."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
(root / "build").mkdir(exist_ok=True)
for aw, dw, spares, latency in [(a, d, s, l) for a, d, s in [(1, 1, 1), (1, 3, 2), (2, 8, 1), (3, 4, 3), (4, 8, 2), (4, 16, 4), (5, 32, 2)] for l in (0, 1)]:
    binary = root / "build" / f"system_{aw}_{dw}_{spares}_{latency}"
    subprocess.run([
        "iverilog", "-g2012", "-s", "tb_system",
        f"-Ptb_system.READ_LATENCY={latency}", f"-Ptb_system.AW={aw}", f"-Ptb_system.DW={dw}", f"-Ptb_system.SPARES={spares}",
        "-o", str(binary), "rtl/mbist_bisr.v", "rtl/mbist_subsystem.v", "tests/tb_system.v",
    ], cwd=root, check=True)
    subprocess.run(["vvp", str(binary)], cwd=root, check=True)

for latency in (0, 1):
    binary = root / "build" / f"ram_{latency}"
    subprocess.run([
        "iverilog", "-g2012", "-s", "tb_ram", f"-Ptb_ram.READ_LATENCY={latency}",
        "-o", str(binary), "rtl/mbist_bisr.v", "rtl/mbist_subsystem.v",
        "rtl/mbist_ram.v", "tests/tb_ram.v",
    ], cwd=root, check=True)
    subprocess.run(["vvp", str(binary)], cwd=root, check=True)

for latency in (0, 1):
    binary = root / "build" / f"cocotb_fixture_{latency}"
    subprocess.run([
        "iverilog", "-g2012", "-s", "tb_cocotb_fixture", f"-Ptb_cocotb_fixture.READ_LATENCY={latency}",
        "-o", str(binary), "rtl/mbist_bisr.v", "rtl/mbist_subsystem.v",
        "tests/cocotb_top.v", "tests/tb_cocotb_fixture.v",
    ], cwd=root, check=True)
    subprocess.run(["vvp", str(binary)], cwd=root, check=True)

for latency in (0, 1):
    binary = root / "build" / f"memory_{latency}"
    subprocess.run([
        "iverilog", "-g2012", "-s", "tb_memory", f"-Ptb_memory.READ_LATENCY={latency}",
        "-o", str(binary), "rtl/mbist_bisr.v", "rtl/mbist_subsystem.v",
        "rtl/mbist_ram.v", "rtl/mbist_memory.v", "tests/tb_memory.v",
    ], cwd=root, check=True)
    subprocess.run(["vvp", str(binary)], cwd=root, check=True)
