"""Bounded clean/single-fault memory proof with Yosys' built-in SAT solver."""
from pathlib import Path
import json
import subprocess

root = Path(__file__).resolve().parents[1]
work = root / 'build' / 'formal'
work.mkdir(parents=True, exist_ok=True)
results = []
for latency, fault in [(l, f) for l in (0, 1) for f in (0, 1)]:
    depth = (10 + 5 * latency) * 5 + 5
    script = f'''
read_verilog -formal -sv rtl/mbist_bisr.v formal/clean_memory.v
chparam -set READ_LATENCY {latency} -set INJECT_FAULT {fault} clean_memory
prep -top clean_memory -flatten
memory_map
opt
sat -seq {depth} -set-assumes -prove-asserts -verify -dump_vcd {work / f'failure_{latency}_{fault}.vcd'}
'''
    (work / f'proof_{latency}_{fault}.ys').write_text(script)
    run = subprocess.run(['yosys', '-Q', '-p', script], cwd=root, capture_output=True, text=True, timeout=120)
    (work / f'proof_{latency}_{fault}.log').write_text(run.stdout + run.stderr)
    passed = run.returncode == 0 and 'SUCCESS!' in run.stdout
    results.append({'latency': latency, 'fault': fault, 'steps': depth, 'passed': passed,
                    'scope': 'AW=1 DW=2 SPARES=1; clean or one symbolic stuck-bit row; arbitrary initial RAM; one reset/start'})
    (work / 'report.json').write_text(json.dumps(results, indent=2) + '\n')
    if not passed:
        raise RuntimeError(f'Formal proof failed; see {work / f"proof_{latency}_{fault}.log"}')
    print(f'PASS bounded memory proof latency={latency}, fault={fault}, steps={depth}', flush=True)
