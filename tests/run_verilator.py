"""Second-simulator integration checks for boundary/default geometry and latency.

Cached executables are reused only when source, parameters and tool signatures
match. A fresh simulation is always run and its log retained.
"""
from pathlib import Path
import hashlib
import json
import subprocess

root = Path(__file__).resolve().parents[1]
work = root / 'build' / 'verilator'
work.mkdir(parents=True, exist_ok=True)
sources = ['rtl/mbist_bisr.v', 'rtl/mbist_subsystem.v', 'tests/tb_system.v']
version = subprocess.check_output(['verilator', '--version'], text=True).strip()
compiler = subprocess.check_output(['g++', '--version'], text=True).splitlines()[0]
results = []
for aw, dw, spares in [(1, 1, 1), (4, 8, 2)]:
    for latency in (0, 1):
        name = f'system_{aw}_{dw}_{spares}_{latency}'
        directory = work / name
        directory.mkdir(exist_ok=True)
        binary = directory / 'sim'
        command = ['verilator', '--binary', '--timing', '--assert', '-j', '2', '-CFLAGS', '-O0',
                   '--top-module', 'tb_system', '--Mdir', str(directory), '-o', 'sim',
                   f'-GAW={aw}', f'-GDW={dw}', f'-GSPARES={spares}', f'-GREAD_LATENCY={latency}', *sources]
        signature = {'command': command, 'verilator': version, 'compiler': compiler,
                     'sources': {s: hashlib.sha256((root / s).read_bytes()).hexdigest() for s in sources}}
        stamp = directory / 'build_signature.json'
        cached = binary.exists() and stamp.exists() and json.loads(stamp.read_text()) == signature
        if not cached:
            print(f'Building Verilator {name}...', flush=True)
            with (directory / 'build.log').open('w') as log:
                built = subprocess.run(command, cwd=root, stdout=log, stderr=subprocess.STDOUT, timeout=180)
            if built.returncode:
                raise RuntimeError(f'Verilator build failed: {directory / "build.log"}')
            stamp.write_text(json.dumps(signature, indent=2) + '\n')
        run = subprocess.run([str(binary)], cwd=root, capture_output=True, text=True, timeout=30)
        (directory / 'simulation.log').write_text(run.stdout + run.stderr)
        passed = run.returncode == 0 and 'PASS system' in run.stdout
        results.append({'configuration': name, 'passed': passed, 'reused_build': cached,
                        'verilator': version, 'compiler': compiler})
        (work / 'report.json').write_text(json.dumps(results, indent=2) + '\n')
        if not passed:
            raise RuntimeError(f'Verilator simulation failed: {directory / "simulation.log"}')
        print(f'PASS Verilator {name}', flush=True)
