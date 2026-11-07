"""Seeded physical stuck-bit campaign checked by an independent March oracle.

No simulator Python binding is needed. Every memory command, diagnosis field,
repair mapping and successful post-repair user access is checked against RTL.
"""
import argparse
import hashlib
import json
from pathlib import Path
import random
import subprocess
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
DEPTH, SPARES, MASK = 16, 4, 255


def oracle(zero, one, latency):
    memory = [0] * (DEPTH + SPARES)
    bad_spares, mapping, trace = set(), {}, []
    failures, first, unrepairable = 0, None, False
    # Explicit algorithm specification, independent of controller state encodings.
    march = [(False, [('w', 0)]),
             (False, [('r', 0), ('w', MASK)]),
             (False, [('r', MASK), ('w', 0)]),
             (True, [('r', 0), ('w', MASK)]),
             (True, [('r', MASK), ('w', 0)]),
             (False, [('r', 0)])]
    for stage in ('spares', 'diagnose', 'verify'):
        count = SPARES if stage == 'spares' else DEPTH
        for descending, operations in march:
            addresses = range(count - 1, -1, -1) if descending else range(count)
            for logical in addresses:
                physical = DEPTH + logical if stage == 'spares' else mapping.get(logical, logical) if stage == 'verify' else logical
                for op, data in operations:
                    trace.append((physical, int(op == 'w'), data if op == 'w' else 0))
                    if op == 'w':
                        memory[physical] = data
                        continue
                    observed = (memory[physical] & ~zero[physical]) | one[physical]
                    if observed == data:
                        continue
                    failures += 1
                    if first is None:
                        first = (physical, observed ^ data)
                    if stage == 'spares':
                        bad_spares.add(physical)
                    elif stage == 'verify':
                        unrepairable = True
                    elif logical not in mapping:
                        available = sorted(set(range(DEPTH, DEPTH + SPARES)) - bad_spares - set(mapping.values()))
                        if available:
                            mapping[logical] = available[0]
                        else:
                            unrepairable = True
    first = first or (0, 0)
    status = [(10 + 5 * latency) * (2 * DEPTH + SPARES), int(failures > 0),
              int(unrepairable), int(not unrepairable), min(failures, 31),
              *first, sum(1 << (a - DEPTH) for a in bad_spares)]
    return trace, status, [mapping.get(a, a) for a in range(DEPTH)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--seed', type=int, default=20261105)
    parser.add_argument('--cases', type=int, default=100)
    args = parser.parse_args()
    if args.cases < 1:
        parser.error('--cases must be positive')
    work = ROOT / 'build' / 'campaign'
    work.mkdir(parents=True, exist_ok=True)
    sources = ['rtl/mbist_bisr.v', 'rtl/mbist_subsystem.v', 'tests/tb_campaign.v', 'tests/run_campaign.py']
    report = {'seed': args.seed, 'cases_per_latency': args.cases, 'started_utc': datetime.now(timezone.utc).isoformat(),
              'source_sha256': {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in sources},
              'status': 'running', 'passed': 0, 'failed': 0, 'results': []}
    rng = random.Random(args.seed)
    cases = []
    for index in range(args.cases):
        zero, one = [0] * 20, [0] * 20
        # First case clean; subsequent cases cover varied fault populations.
        count = 0 if index == 0 else rng.randrange(1, 11)
        for address in rng.sample(range(20), count):
            bits = rng.randrange(1, 256)
            zero[address] = bits & rng.randrange(256)
            one[address] = bits & ~zero[address]
        cases.append((zero, one))
    try:
        for latency in (0, 1):
            binary = work / f'sim_{latency}'
            subprocess.run(['iverilog', '-g2012', '-s', 'tb_campaign',
                            f'-Ptb_campaign.READ_LATENCY={latency}', '-o', str(binary), *sources[:3]], cwd=ROOT, check=True)
            for index, (zero, one) in enumerate(cases):
                directory = work / f'latency_{latency}_case_{index:04d}'
                directory.mkdir(exist_ok=True)
                for name, values in [('zero', zero), ('one', one)]:
                    (directory / f'{name}.hex').write_text(''.join(f'{v:02x}\n' for v in values))
                result = subprocess.run(['vvp', str(binary),
                    f'+zero={directory / "zero.hex"}', f'+one={directory / "one.hex"}',
                    f'+trace={directory / "trace.txt"}', f'+result={directory / "result.txt"}'],
                    cwd=ROOT, capture_output=True, text=True, timeout=20)
                (directory / 'simulation.log').write_text(result.stdout + result.stderr)
                try:
                    assert result.returncode == 0, result.stdout + result.stderr
                    trace, status, mapping = oracle(zero, one, latency)
                    actual_trace = [tuple(map(int, line.split())) for line in (directory / 'trace.txt').read_text().splitlines()]
                    rows = (directory / 'result.txt').read_text().splitlines()
                    assert actual_trace == trace, 'March command trace differs from oracle'
                    assert list(map(int, rows[0].split())) == status, f'diagnosis differs: got {rows[0]}, expected {status}'
                    assert [int(v) for v in rows[1:]] == mapping, 'repair mapping differs'
                except Exception as error:
                    report['failed'] += 1
                    report['results'].append({'latency': latency, 'case': index, 'passed': False, 'error': str(error)})
                    raise
                report['passed'] += 1
                report['results'].append({'latency': latency, 'case': index, 'passed': True,
                                          'repair_pass': bool(status[3]), 'fault_found': bool(status[1]),
                                          'bad_spares': status[-1]})
            print(f'PASS independent March/fault campaign: latency={latency}, cases={args.cases}, seed={args.seed}', flush=True)
        report['status'] = 'passed'
    except BaseException as error:
        report['status'] = 'failed'
        report['error'] = str(error)
        raise
    finally:
        report['finished_utc'] = datetime.now(timezone.utc).isoformat()
        (work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f'Report: {work / "report.json"}')


if __name__ == '__main__':
    main()
