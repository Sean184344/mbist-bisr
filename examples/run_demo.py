"""Run real RTL fault scenarios and show observed diagnosis and repair outcomes."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tests'))
from run_campaign import oracle


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--latency', type=int, choices=(0, 1), default=1)
    parser.add_argument('--scenario', choices=('all', 'clean', 'repaired', 'bad_spare', 'exhausted'), default='all')
    parser.add_argument('--waves', action='store_true')
    args = parser.parse_args()
    work = ROOT / 'build' / 'demo' / f'latency_{args.latency}'
    work.mkdir(parents=True, exist_ok=True)
    binary = work / 'sim'
    subprocess.run(['iverilog', '-g2012', '-s', 'tb_campaign',
                    f'-Ptb_campaign.READ_LATENCY={args.latency}', '-o', str(binary),
                    'rtl/mbist_bisr.v', 'rtl/mbist_subsystem.v', 'tests/tb_campaign.v'], cwd=ROOT, check=True)
    scenarios = {
        'clean': [],
        'repaired': [(3, 1, 0), (7, 0, 128)],
        'bad_spare': [(3, 1, 0), (16, 1, 0)],
        'exhausted': [(a, 1, 0) for a in (1, 3, 5, 7, 9)],
    }
    report = {'geometry': {'address_bits': 4, 'data_bits': 8, 'spares': 4, 'read_latency': args.latency},
              'note': 'Injected fault classes are known from the testbench; RTL reports observations, not unique physical defect classifications.',
              'scenarios': []}
    for name, faults in scenarios.items():
        if args.scenario not in ('all', name):
            continue
        directory = work / name
        directory.mkdir(exist_ok=True)
        zero, one = [0] * 20, [0] * 20
        for address, mask_zero, mask_one in faults:
            zero[address], one[address] = mask_zero, mask_one
        for label, values in [('zero', zero), ('one', one)]:
            (directory / f'{label}.hex').write_text(''.join(f'{v:02x}\n' for v in values))
        command = ['vvp', str(binary), f'+zero={directory / "zero.hex"}', f'+one={directory / "one.hex"}',
                   f'+trace={directory / "trace.txt"}', f'+result={directory / "result.txt"}']
        if args.waves:
            command.append(f'+waves={directory / "wave.vcd"}')
        run = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=20)
        (directory / 'simulation.log').write_text(run.stdout + run.stderr)
        if run.returncode:
            raise RuntimeError(f'Demo failed: {directory / "simulation.log"}')
        rows = (directory / 'result.txt').read_text().splitlines()
        status = list(map(int, rows[0].split()))
        mapping = [int(v) for v in rows[1:]]
        trace = [tuple(map(int, row.split())) for row in (directory / 'trace.txt').read_text().splitlines()]
        expected_trace, expected_status, expected_map = oracle(zero, one, args.latency)
        assert (trace, status, mapping) == (expected_trace, expected_status, expected_map), 'RTL disagrees with oracle'
        cycles, found, exhausted, passed, count, first, mask, bad_spares = status
        repairs = {str(a): physical for a, physical in enumerate(mapping) if a != physical}
        entry = {'scenario': name, 'cycles': cycles, 'fault_found': bool(found), 'unrepairable': bool(exhausted),
                 'repair_pass': bool(passed), 'failing_reads_saturated': count,
                 'first_failure': {'physical_address': first, 'xor_mask': mask} if found else None,
                 'bad_spare_bitmap': bad_spares, 'mapping': repairs,
                 'normal_user_access_checked': bool(passed),
                 'injected_faults': [{'physical_address': a, 'stuck_zero_mask': z, 'stuck_one_mask': o} for a, z, o in faults]}
        report['scenarios'].append(entry)
        print(f'{name}: {"PASS" if passed else "UNREPAIRABLE"}; {cycles} cycles; failing reads={count}')
        if found:
            print(f'  first mismatch: physical address {first}, XOR mask 0x{mask:02x}')
        print(f'  rejected spares: 0b{bad_spares:04b}; remapping: {repairs or "none"}')
    (work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f'Report: {work / "report.json"}')


if __name__ == '__main__':
    main()
