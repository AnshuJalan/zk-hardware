"""Runs every multiplier configuration with cocotb and prints a summary table (`python3 tb/mul/test_mul.py [filter]` or `pytest tb/mul/test_mul.py`)."""

import json
import os
import sys
import time
from dataclasses import dataclass
from pathlib import Path

import pytest
from cocotb_tools.runner import get_results, get_runner

TB_DIR = Path(__file__).resolve().parent
REPO = TB_DIR.parents[1]
RTL = REPO / "parametrized_primitives"
BUILD_ROOT = TB_DIR / "sim_build"
SIM = os.environ.get("SIM", "verilator")
SEED = int(os.environ.get("MUL_SEED", "20261025"))

# The cocotb runner forwards sys.path to the simulator as PYTHONPATH.
for path in (TB_DIR, REPO / "reference"):
    if str(path) not in sys.path:
        sys.path.insert(0, str(path))

SOURCES = {
    "mul_behav": ["mul_behav.sv"],
    "mul_comb": ["csa_3_2.sv", "mul_comb.sv"],
    "mul_iter_csa": ["mul_iter_csa.sv"],
    "mul_digit_serial": ["csa_3_2.sv", "mul_digit_serial.sv"],
    "mul_pipe": ["csa_3_2.sv", "mul_pipe.sv"],
}

TESTS = {
    "mul_behav": "test_comb",
    "mul_comb": "test_comb",
    "mul_iter_csa": "test_seq",
    "mul_digit_serial": "test_seq",
    "mul_pipe": "test_pipe",
}


@dataclass
class Config:
    top: str
    params: dict
    mode: str
    n_random: int = 0

    @property
    def name(self):
        return self.top + "".join(f"_{k}{v}" for k, v in self.params.items())


def make_configs():
    configs = []
    # W=8 is exhaustive (65536 pairs). Each module finishes well under the 2 minute budget.
    # W=64 uses corner cases plus 2000 random pairs.
    for w, mode, n_random in ((8, "exhaustive", 0), (64, "random", 2000)):
        configs += [
            Config("mul_behav", {"W": w}, mode, n_random),
            Config("mul_comb", {"W": w}, mode, n_random),
            Config("mul_iter_csa", {"W": w}, mode, n_random),
        ]
        configs += [Config("mul_digit_serial", {"W": w, "D": d}, mode, n_random) for d in (1, 2, 4)]
        configs += [Config("mul_pipe", {"W": w, "STAGES": s}, mode, n_random) for s in (1, 2, 4, 8)]
    return configs


CONFIGS = make_configs()


def run(cfg):
    build_dir = BUILD_ROOT / cfg.name
    build_dir.mkdir(parents=True, exist_ok=True)
    stats_file = build_dir / "stats.json"
    stats_file.unlink(missing_ok=True)

    runner = get_runner(SIM)
    t0 = time.monotonic()
    runner.build(
        sources=[RTL / f for f in SOURCES[cfg.top]],
        hdl_toplevel=cfg.top,
        parameters=cfg.params,
        build_dir=build_dir,
        timescale=("1ns", "1ps"),
        log_file=build_dir / "build.log",
    )
    t1 = time.monotonic()
    results = runner.test(
        test_module="mul_tb",
        hdl_toplevel=cfg.top,
        testcase=TESTS[cfg.top],
        build_dir=build_dir,
        test_dir=build_dir,
        results_xml=str(build_dir / "results.xml"),
        timescale=("1ns", "1ps"),
        log_file=build_dir / "test.log",
        extra_env={
            "MUL_MODE": cfg.mode,
            "MUL_N_RANDOM": str(cfg.n_random),
            "MUL_SEED": str(SEED),
            "MUL_D": str(cfg.params.get("D", 0)),
            "MUL_STAGES": str(cfg.params.get("STAGES", 0)),
            "MUL_STATS": str(stats_file),
        },
    )
    t2 = time.monotonic()

    n_tests, n_failed = get_results(results)
    stats = json.loads(stats_file.read_text()) if stats_file.exists() else {}
    return {
        "cfg": cfg,
        "passed": n_tests > 0 and n_failed == 0 and stats.get("errors") == 0,
        "build_s": t1 - t0,
        "sim_s": t2 - t1,
        "log": build_dir / "test.log",
        **stats,
    }


def format_row(r):
    cfg = r["cfg"]
    params = ", ".join(f"{k}={v}" for k, v in cfg.params.items())
    vectors = r.get("vectors")
    tests = f"{vectors} {cfg.mode}" if vectors is not None else "-"
    if cfg.top in ("mul_behav", "mul_comb"):
        latency, throughput = "comb", "1 / eval"
    elif "lat_min" not in r:
        latency, throughput = "-", "-"
    elif cfg.top == "mul_pipe":
        latency = f"{r['lat_min']}/{r['lat_max']}"
        throughput = f"{r['sustained_throughput']:.2f} / cycle"
    else:
        latency = f"{r['lat_min']}/{r['lat_max']}"
        throughput = f"1 / {r['cycles_per_op']:.2f} cycles"
    return [
        cfg.top,
        params,
        tests,
        "PASS" if r["passed"] else "FAIL",
        latency,
        throughput,
        f"{r['sim_s']:.1f}s",
    ]


def print_summary(rows):
    header = ["module", "parameters", "tests run", "result", "latency min/max", "throughput", "sim time"]
    table = [header] + [format_row(r) for r in rows]
    widths = [max(len(row[i]) for row in table) for i in range(len(header))]
    sep = "-+-".join("-" * w for w in widths)
    print()
    for i, row in enumerate(table):
        print(" | ".join(cell.ljust(w) for cell, w in zip(row, widths)))
        if i == 0:
            print(sep)
    print()
    print("Latency counts cycles from the cycle start or in_valid is high to the cycle done or out_valid is high.")
    print("Sequential throughput assumes start is reissued in the first idle cycle after done.")
    print("mul_pipe throughput is measured over a back-to-back burst of a quarter of the vectors.")
    print(f"Simulator: {SIM}. Seed: {SEED}.")


@pytest.mark.parametrize("cfg", CONFIGS, ids=lambda c: c.name)
def test_mul(cfg):
    r = run(cfg)
    assert r["passed"], f"{cfg.name} failed, see {r['log']}"


def main(filters):
    rows = []
    for cfg in CONFIGS:
        if filters and not any(f in cfg.name for f in filters):
            continue
        print(f"Running {cfg.name} ...", flush=True)
        rows.append(run(cfg))
    print_summary(rows)
    return 0 if all(r["passed"] for r in rows) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
