"""Bounded proofs of repaired user accesses before/after retest and reset."""
from pathlib import Path
import json
import subprocess

root = Path(__file__).resolve().parents[1]
work = root / 'build' / 'formal_port'
work.mkdir(parents=True, exist_ok=True)
results = []
for latency in (0, 1):
    for reset in (0, 1):
        steps = 2 * (10 + 5 * latency) * 5 + 25
        name = f'latency_{latency}_reset_{reset}'
        script = f'''
read_verilog -formal -sv rtl/mbist_bisr.v rtl/mbist_subsystem.v formal/user_port.v
chparam -set READ_LATENCY {latency} -set RESET_RETEST {reset} user_port
prep -top user_port -flatten
memory_map
opt
sat -seq {steps} -set-assumes -prove-asserts -verify -dump_vcd {work / (name + '.vcd')}
'''
        (work / f'{name}.ys').write_text(script)
        with (work / f'{name}.log').open('w') as log:
            run = subprocess.run(['yosys', '-Q', '-p', script], cwd=root, stdout=log, stderr=subprocess.STDOUT, timeout=180)
        passed = run.returncode == 0 and 'SUCCESS!' in (work / f'{name}.log').read_text()
        results.append({'latency': latency, 'reset_before_retest': reset, 'steps': steps, 'passed': passed,
                        'scope': 'AW=1 DW=2 SPARES=1; symbolic single faulty row; arbitrary user traffic; two complete MBIST runs'})
        (work / 'report.json').write_text(json.dumps(results, indent=2) + '\n')
        if not passed:
            raise RuntimeError(f'User-port proof failed: {work / (name + ".log")}')
        print(f'PASS user-port proof {name} steps={steps}', flush=True)
