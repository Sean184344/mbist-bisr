"""Integrated Cocotb regression for both memory read latencies (Cocotb 2.x)."""
import os
import random
import cocotb
from cocotb.triggers import Timer
from run_campaign import oracle

LATENCY = int(os.environ.get('READ_LATENCY', '0'))
CYCLES = (10 + 5 * LATENCY) * 36


def packed(values):
    return sum(value << (8 * address) for address, value in enumerate(values))


async def tick(d, trace=None):
    d.clk.value = 0
    await Timer(5, unit='ns')
    if trace is not None and int(d.busy.value) and int(d.mem_en.value):
        write = int(d.mem_we.value)
        trace.append((int(d.mem_addr.value), write, int(d.mem_wdata.value) if write else 0))
    d.clk.value = 1
    await Timer(5, unit='ns')


async def initialize(d):
    for name in ('clk', 'rst_n', 'start', 'user_en', 'user_we', 'user_addr',
                 'user_wdata', 'stuck_zero', 'stuck_one'):
        getattr(d, name).value = 0
    await tick(d)
    d.rst_n.value = 1
    await Timer(1, unit='ns')
    assert not int(d.user_ready.value)


@cocotb.test()
async def march_diagnosis_and_user_access(d):
    await initialize(d)
    rng = random.Random(20261105)
    cases = []
    # Healthy, single fault, exhausted spares, rejected spare, and all-spare faults.
    for addresses in ([], [3], [1, 3, 5, 7, 9], [3, 16], [16, 17, 18, 19]):
        zero, one = [0] * 20, [0] * 20
        for address in addresses:
            zero[address] = 1
        cases.append((zero, one))
    for _ in range(10):
        zero, one = [0] * 20, [0] * 20
        for address in rng.sample(range(20), rng.randrange(1, 11)):
            mask = rng.randrange(1, 256)
            zero[address] = mask & rng.randrange(256)
            one[address] = mask & ~zero[address]
        cases.append((zero, one))
    for zero, one in cases:
        d.stuck_zero.value, d.stuck_one.value = packed(zero), packed(one)
        d.user_en.value = 0
        d.start.value = 1
        await tick(d)
        d.start.value = 0
        trace = []
        for cycle in range(CYCLES):
            assert int(d.busy.value) and not int(d.user_ready.value)
            await tick(d, trace)
        assert int(d.done.value) and not int(d.busy.value)
        expected_trace, expected_status, expected_map = oracle(zero, one, LATENCY)
        actual_status = [CYCLES] + [int(getattr(d, name).value) for name in
            ('fault_found', 'unrepairable', 'repair_pass', 'fail_count',
             'first_fail_addr', 'first_fail_mask', 'spare_bad')]
        assert trace == expected_trace
        assert actual_status == expected_status
        for address, physical in enumerate(expected_map):
            d.user_addr.value = address
            await Timer(1, unit='ns')
            assert int(d.mem_addr.value) == physical
        if expected_status[3]:
            d.user_en.value = 1
            d.user_we.value = 1
            for address in range(16):
                d.user_addr.value, d.user_wdata.value = address, address * 13
                await tick(d)
            d.user_we.value = 0
            for address in range(16):
                d.user_addr.value = address
                if LATENCY:
                    await tick(d)
                else:
                    await Timer(1, unit='ns')
                assert int(d.user_rvalid.value)
                assert int(d.user_rdata.value) == address * 13
                if not LATENCY:
                    await tick(d)
            d.user_en.value = 0
            await Timer(1, unit='ns')
            assert int(d.user_rvalid.value) == LATENCY
            await tick(d)
            assert not int(d.user_rvalid.value)
        else:
            d.user_en.value, d.user_we.value = 1, 1
            await Timer(1, unit='ns')
            assert not int(d.user_ready.value) and not int(d.mem_en.value)
            d.user_en.value = 0


@cocotb.test()
async def abort_each_stage_and_restart(d):
    await initialize(d)
    cost = 10 + 5 * LATENCY
    for offset in (3, cost * 4 + 3, cost * 20 + 3):
        d.start.value = 1
        await tick(d)
        d.start.value = 0
        for _ in range(offset):
            await tick(d)
        assert int(d.busy.value)
        d.rst_n.value = 0
        d.user_en.value, d.user_we.value = 1, 1
        await Timer(1, unit='ns')
        assert not int(d.mem_en.value) and not int(d.user_rvalid.value)
        await tick(d)
        for name in ('busy', 'done', 'repair_pass', 'fault_found', 'unrepairable', 'spare_bad', 'fail_count'):
            assert int(getattr(d, name).value) == 0
        d.rst_n.value = 1
        d.user_en.value = 0
    d.start.value = 1
    await tick(d)
    d.start.value = 0
    for _ in range(CYCLES):
        await tick(d)
    assert int(d.done.value) and int(d.repair_pass.value)
