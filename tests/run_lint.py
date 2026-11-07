"""Strict Verilator lint; explicit optional dependency, no warning suppression."""
from pathlib import Path
import json
import subprocess

root = Path(__file__).resolve().parents[1]
work = root / 'build' / 'lint'
work.mkdir(parents=True, exist_ok=True)
results = []
for aw, dw, spares in [(1, 1, 1), (1, 3, 2), (2, 8, 1), (3, 4, 3), (4, 8, 2), (4, 16, 4), (5, 32, 2)]:
    for latency in (0, 1):
        for top in ('mbist_subsystem', 'mbist_ram', 'mbist_memory'):
            sources = ['rtl/mbist_bisr.v', 'rtl/mbist_subsystem.v'] if top == 'mbist_subsystem' else ['rtl/mbist_ram.v']
            if top == 'mbist_memory':
                sources = ['rtl/mbist_bisr.v', 'rtl/mbist_subsystem.v', 'rtl/mbist_ram.v', 'rtl/mbist_memory.v']
            name = f'{top}_{aw}_{dw}_{spares}_{latency}'
            run = subprocess.run(['verilator', '--lint-only', '-Wall', '--top-module', top,
                                  f'-GAW={aw}', f'-GDW={dw}', f'-GSPARES={spares}',
                                  f'-GREAD_LATENCY={latency}', *sources], cwd=root, capture_output=True, text=True)
            (work / f'{name}.log').write_text(run.stdout + run.stderr)
            results.append({'configuration': name, 'passed': run.returncode == 0})
            (work / 'report.json').write_text(json.dumps(results, indent=2) + '\n')
            if run.returncode:
                raise RuntimeError(f'Lint failed: {work / f"{name}.log"}')
print(f'PASS strict Verilator lint: {len(results)} configurations')
