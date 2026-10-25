"""cocotb tests that check every multiplier in rtl/mul/rtl/ against reference/mul/mul_ref.py."""

import itertools
import json
import os
import random
from collections import deque

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, Timer

from mul_ref import mul_ref

MAX_LOGGED_ERRORS = 10


def corner_pairs(w):
    ones = (1 << w) - 1
    alt_lo = sum(1 << i for i in range(0, w, 2))
    alt_hi = ones ^ alt_lo
    msb = 1 << (w - 1)
    base = {0, 1, 2, 3, ones, ones - 1, alt_lo, alt_hi, msb, msb - 1, msb + 1}
    pairs = set(itertools.product(base, repeat=2))
    for i in range(w):
        pow2 = 1 << i
        pairs |= {(pow2, ones), (ones, pow2), (pow2, pow2), (pow2, 1), (pow2, alt_lo), (alt_hi, pow2)}
    return sorted(pairs)


def stimulus(w):
    rng = random.Random(int(os.environ.get("MUL_SEED", "1")))
    if os.environ.get("MUL_MODE") == "exhaustive":
        pairs = list(itertools.product(range(1 << w), repeat=2))
    else:
        n = int(os.environ.get("MUL_N_RANDOM", "2000"))
        pairs = corner_pairs(w) + [(rng.getrandbits(w), rng.getrandbits(w)) for _ in range(n)]
    rng.shuffle(pairs)
    return pairs, rng


def write_stats(**stats):
    path = os.environ.get("MUL_STATS")
    if path:
        with open(path, "w") as f:
            json.dump(stats, f)


class Checker:
    def __init__(self, dut, w):
        self.dut = dut
        self.w = w
        self.errors = 0

    def error(self, msg):
        self.errors += 1
        if self.errors <= MAX_LOGGED_ERRORS:
            self.dut._log.error(msg)

    def check(self, a, b, got):
        exp = mul_ref(a, b, self.w)
        if got != exp:
            self.error(f"a={a:#x} b={b:#x}: got {got:#x}, expected {exp:#x}")


async def reset(dut, idle_inputs):
    dut.rst_n.value = 0
    for name, value in idle_inputs.items():
        getattr(dut, name).value = value
    Clock(dut.clk, 10, unit="ns").start()
    for _ in range(3):
        await FallingEdge(dut.clk)
    dut.rst_n.value = 1
    await FallingEdge(dut.clk)


@cocotb.test()
async def test_comb(dut):
    """Checks a combinational multiplier one pair at a time."""
    w = len(dut.a)
    pairs, _ = stimulus(w)
    chk = Checker(dut, w)

    for a, b in pairs:
        dut.a.value = a
        dut.b.value = b
        await Timer(1, unit="ns")
        chk.check(a, b, dut.p.value.to_unsigned())

    write_stats(vectors=len(pairs), errors=chk.errors)
    assert chk.errors == 0, f"{chk.errors} mismatches"


@cocotb.test()
async def test_seq(dut):
    """Checks the start/done/p contract of mul_iter_csa and mul_digit_serial.

    Each pair is started in a cycle where the DUT is idle. While the multiply is in
    flight the test drives random start, a and b, which the DUT must ignore. It checks
    that p holds its previous value until done, that p is correct when done is high,
    and that done drops after exactly one cycle with p still held.
    """
    w = len(dut.a)
    d = int(os.environ.get("MUL_D", "0"))
    expected_latency = w // d + 2 if d else None
    timeout = 4 * w + 16
    pairs, rng = stimulus(w)
    chk = Checker(dut, w)

    await reset(dut, {"start": 0, "a": 0, "b": 0})
    if dut.done.value != 0 or dut.p.value.to_unsigned() != 0:
        chk.error("done or p is not zero after reset")

    held_p = 0
    latencies = []
    total_cycles = 0

    for a, b in pairs:
        dut.start.value = 1
        dut.a.value = a
        dut.b.value = b

        cycles = 0
        while True:
            await FallingEdge(dut.clk)
            cycles += 1
            dut.start.value = rng.getrandbits(1)
            dut.a.value = rng.getrandbits(w)
            dut.b.value = rng.getrandbits(w)

            p = dut.p.value.to_unsigned()
            if dut.done.value:
                break
            if p != held_p:
                chk.error(f"a={a:#x} b={b:#x}: p changed to {p:#x} before done in cycle {cycles}")
            if cycles >= timeout:
                chk.error(f"a={a:#x} b={b:#x}: no done after {timeout} cycles")
                assert False, "timeout"

        chk.check(a, b, p)
        latencies.append(cycles)
        if expected_latency is not None and cycles != expected_latency:
            chk.error(f"a={a:#x} b={b:#x}: latency {cycles}, expected constant {expected_latency}")

        # The DUT returns to idle one cycle after done.
        await FallingEdge(dut.clk)
        total_cycles += cycles + 1
        held_p = p
        if dut.done.value:
            chk.error(f"a={a:#x} b={b:#x}: done stayed high for more than one cycle")
        if dut.p.value.to_unsigned() != held_p:
            chk.error(f"a={a:#x} b={b:#x}: p was not held after done")

    write_stats(
        vectors=len(pairs),
        errors=chk.errors,
        lat_min=min(latencies),
        lat_max=max(latencies),
        cycles_per_op=total_cycles / len(pairs),
    )
    assert chk.errors == 0, f"{chk.errors} errors"


@cocotb.test()
async def test_pipe(dut):
    """Streams pairs through mul_pipe and checks results in order with a scoreboard.

    The first quarter of the pairs streams back to back to measure sustained throughput.
    The rest streams with random valid gaps, during which a and b carry random junk.
    """
    w = len(dut.a)
    stages = int(os.environ["MUL_STAGES"])
    pairs, rng = stimulus(w)
    chk = Checker(dut, w)

    n_burst = max(1, len(pairs) // 4)
    schedule = list(pairs[:n_burst])
    for pair in pairs[n_burst:]:
        while rng.random() < 0.3:
            schedule.append(None)
        schedule.append(pair)
    schedule += [None] * (stages + 4)

    await reset(dut, {"in_valid": 0, "a": 0, "b": 0})

    pending = deque()
    sent = 0
    latencies = []
    burst_out_cycles = []

    for cycle, item in enumerate(schedule):
        if dut.out_valid.value:
            p = dut.p.value.to_unsigned()
            if not pending:
                chk.error(f"cycle {cycle}: out_valid with no pair in flight")
            else:
                in_cycle, a, b, idx = pending.popleft()
                chk.check(a, b, p)
                latencies.append(cycle - in_cycle)
                if idx < n_burst:
                    burst_out_cycles.append(cycle)

        if item is None:
            dut.in_valid.value = 0
            dut.a.value = rng.getrandbits(w)
            dut.b.value = rng.getrandbits(w)
        else:
            a, b = item
            dut.in_valid.value = 1
            dut.a.value = a
            dut.b.value = b
            pending.append((cycle, a, b, sent))
            sent += 1

        await FallingEdge(dut.clk)

    if pending:
        chk.error(f"{len(pending)} pairs never produced out_valid")
    bad_latency = sorted(set(latencies) - {stages})
    if bad_latency:
        chk.error(f"latencies {bad_latency} seen, expected exactly {stages}")

    burst_span = burst_out_cycles[-1] - burst_out_cycles[0] + 1 if burst_out_cycles else 1
    write_stats(
        vectors=len(pairs),
        errors=chk.errors,
        lat_min=min(latencies, default=0),
        lat_max=max(latencies, default=0),
        sustained_throughput=len(burst_out_cycles) / burst_span,
        overall_throughput=len(latencies) / len(schedule),
    )
    assert chk.errors == 0, f"{chk.errors} errors"
