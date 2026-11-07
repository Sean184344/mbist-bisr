"""Check that the campaign rejects representative broken RTL implementations."""
import json
from pathlib import Path
import subprocess
from run_campaign import oracle

root = Path(__file__).resolve().parents[1]
work = root / 'build' / 'mutations'
work.mkdir(parents=True, exist_ok=True)
original = (root / 'rtl/mbist_bisr.v').read_text()
mutants = [
    ('wrong_write_background', 'mem_wdata={DW{(phase==1 || phase==3)}};', 'mem_wdata={DW{(phase==1)}};', 0),
    ('ignore_bad_spares', '!valid[k] && !spare_bad[k] && free_slot==-1', '!valid[k] && free_slot==-1', 0),
    ('bypass_verification_mapping', 'if(mode==2)\n', 'if(mode==3)\n', 0),
    ('omit_synchronous_wait', 'READ_LATENCY==1 && !mem_we && !read_pending', "1'b0", 1),
]
zero, one = [0] * 20, [0] * 20
zero[3], zero[16] = 1, 2
for name, values in [('zero', zero), ('one', one)]:
    (work / f'{name}.hex').write_text(''.join(f'{v:02x}\n' for v in values))
results = []
for name, before, after, latency in mutants:
    assert original.count(before) == 1, f'mutation anchor changed: {name}'
    source = work / f'{name}.v'
    source.write_text(original.replace(before, after))
    binary = work / name
    subprocess.run(['iverilog', '-g2012', '-s', 'tb_campaign',
                    f'-Ptb_campaign.READ_LATENCY={latency}', '-o', str(binary),
                    str(source), 'rtl/mbist_subsystem.v', 'tests/tb_campaign.v'], cwd=root, check=True)
    trace_file, result_file = work / f'{name}.trace', work / f'{name}.result'
    run = subprocess.run(['vvp', str(binary), f'+zero={work / "zero.hex"}',
                          f'+one={work / "one.hex"}', f'+trace={trace_file}', f'+result={result_file}'],
                         cwd=root, capture_output=True, text=True, timeout=20)
    (work / f'{name}.log').write_text(run.stdout + run.stderr)
    rejected = run.returncode != 0
    if not rejected:
        trace, status, mapping = oracle(zero, one, latency)
        actual_trace = [tuple(map(int, line.split())) for line in trace_file.read_text().splitlines()]
        rows = result_file.read_text().splitlines()
        rejected = actual_trace != trace or list(map(int, rows[0].split())) != status or [int(v) for v in rows[1:]] != mapping
    results.append({'mutation': name, 'rejected': rejected})
    (work / 'report.json').write_text(json.dumps(results, indent=2) + '\n')
    assert rejected, f'Test failed to reject mutant {name}'
    print(f'PASS mutation rejected: {name}', flush=True)
