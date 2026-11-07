"""Run the portable verification milestone and retain machine-readable evidence."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import shutil
import sys
import time

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / 'scripts'))
from project_manifest import source_files
work = root / 'build' / 'verification'
work.mkdir(parents=True, exist_ok=True)
report = {
    'started_utc': datetime.now(timezone.utc).isoformat(),
    'status': 'running',
    'source_sha256': {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in source_files(root)},
    'stages': [],
    'skipped': [],
    'limitations': ['Cocotb not executed', 'No device timing or vendor RAM mapping',
                    'Formal proofs are bounded and use AW=1 DW=2 SPARES=1',
                    'Verilator simulation covers four representative configurations; Icarus covers fourteen',
                    'Random campaign models static stuck bits; other fault classes use directed examples'],
}
for name, command in [('iverilog', ['iverilog', '-V']), ('yosys', ['yosys', '-V']), ('python', [sys.executable, '--version'])]:
    result = subprocess.run(command, capture_output=True, text=True)
    report.setdefault('tools', {})[name] = (result.stdout or result.stderr).splitlines()[0]


def save():
    (work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')


stages = [
        ('directed_and_matrix', ['make', 'test']),
        ('synthesis', ['make', 'synth']),
        ('diagnosis_demo', ['make', 'demo']),
        ('independent_campaign', [sys.executable, 'tests/run_campaign.py']),
        ('bounded_formal', [sys.executable, 'tests/run_formal.py']),
        ('bounded_user_port', [sys.executable, 'tests/run_port_formal.py']),
        ('checker_mutations', [sys.executable, 'tests/run_mutations.py']),
    ]
if shutil.which('verilator'):
    stages.append(('strict_lint', [sys.executable, 'tests/run_lint.py']))
    if shutil.which('g++'):
        stages.append(('verilator_simulation', [sys.executable, 'tests/run_verilator.py']))
    else:
        report['skipped'].append({'name': 'verilator_simulation', 'reason': 'g++ not installed'})
else:
    report['skipped'].append({'name': 'strict_lint', 'reason': 'Verilator not installed'})
    report['skipped'].append({'name': 'verilator_simulation', 'reason': 'Verilator not installed'})
if shutil.which('cocotb-config'):
    stages.append(('cocotb', ['make', 'cocotb']))
    report['limitations'].remove('Cocotb not executed')
else:
    report['skipped'].append({'name': 'cocotb', 'reason': 'Cocotb not installed'})
save()
try:
    for name, command in stages:
        print(f'Running {name}...', flush=True)
        started = time.monotonic()
        with (work / f'{name}.log').open('w') as log:
            run = subprocess.run(command, cwd=root, stdout=log, stderr=subprocess.STDOUT, timeout=300)
        report['stages'].append({'name': name, 'command': command, 'passed': run.returncode == 0,
                                 'seconds': round(time.monotonic() - started, 3),
                                 'log': str((work / f'{name}.log').relative_to(root))})
        save()
        if run.returncode:
            raise RuntimeError(f'{name} failed: see {work / f"{name}.log"}')
        print(f'PASS {name}', flush=True)
    report['status'] = 'passed'
except BaseException as error:
    report['status'] = 'failed'
    report['error'] = str(error)
    raise
finally:
    report['finished_utc'] = datetime.now(timezone.utc).isoformat()
    save()
print(f'Verification report: {work / "report.json"}')
