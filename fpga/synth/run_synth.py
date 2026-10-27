"""Synthesizes and places each W=64 multiplier on an ECP5 LFE5U-85F and writes benchmarks/stage2/mul_synth.md (`OSS_CAD_SUITE=<path> python3 fpga/synth/run_synth.py [--report-only] [filter]`)."""

import json
import os
import re
import shutil
import statistics
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path

SYNTH_DIR = Path(__file__).resolve().parent
REPO = SYNTH_DIR.parents[1]
BUILD = SYNTH_DIR / "build"
OUT = REPO / "benchmarks" / "stage2"
LOGS = OUT / "logs"
SIM_BUILD = REPO / "rtl" / "mul" / "tb" / "sim_build"

W = 64
SEEDS = (1, 2, 3)
TARGET_MHZ = 200
DEVICE = ["--85k", "--package", "CABGA381", "--speed", "6"]
JOBS = int(os.environ.get("SYNTH_JOBS", "6"))
CELLS = {"LUTs": "LUT4", "FFs": "TRELLIS_FF", "Carry": "CCU2C", "DSPs": "MULT18X18D"}

CSA = "rtl/common/csa_3_2.sv"
MUL = "rtl/mul/rtl"


@dataclass
class Run:
    slug: str
    label: str
    dut: str
    sources: list
    params: dict = field(default_factory=dict)
    nodsp: bool = True
    sim_cfg: str = ""


RUNS = [
    Run("iter_csa", "mul_iter_csa", "mul_iter_csa", [f"{MUL}/mul_iter_csa.sv"], sim_cfg="mul_iter_csa_W64"),
    *(Run(f"digit_serial_d{d}", f"mul_digit_serial D={d}", "mul_digit_serial",
          [CSA, f"{MUL}/mul_digit_serial.sv"], {"D": d}, sim_cfg=f"mul_digit_serial_W64_D{d}")
      for d in (4, 8)),
    *(Run(f"digit_serial_pad_d{d}", f"mul_digit_serial_pad D={d}", "mul_digit_serial_pad",
          [CSA, f"{MUL}/mul_digit_serial_pad.sv"], {"D": d}, sim_cfg=f"mul_digit_serial_pad_W64_D{d}")
      for d in (5, 6)),
    Run("comb", "mul_comb", "mul_comb", [CSA, f"{MUL}/mul_comb.sv"]),
    *(Run(f"pipe_s{s}", f"mul_pipe STAGES={s}", "mul_pipe", [CSA, f"{MUL}/mul_pipe.sv"],
          {"STAGES": s}, sim_cfg=f"mul_pipe_W64_STAGES{s}")
      for s in (4, 8, 16)),
    Run("behav_nodsp", "mul_behav (-nodsp)", "mul_behav", [f"{MUL}/mul_behav.sv"]),
    Run("behav_dsp", "mul_behav (DSP)", "mul_behav", [f"{MUL}/mul_behav.sv"], nodsp=False),
]


def tool(name):
    root = os.environ.get("OSS_CAD_SUITE")
    path = Path(root) / "bin" / name if root else shutil.which(name)
    if not path or not Path(path).exists():
        sys.exit(f"{name} not found. Set OSS_CAD_SUITE to the oss-cad-suite folder or put {name} on PATH.")
    return str(path)


def synth(run):
    build, logs = BUILD / run.slug, LOGS / run.slug
    build.mkdir(parents=True, exist_ok=True)
    logs.mkdir(parents=True, exist_ok=True)
    params = " ".join(f"-G {k}={v}" for k, v in {"W": W, **run.params}.items())
    synth_args = "-top synth_top" + (" -nodsp" if run.nodsp else "")
    script = "\n".join([
        f'read_slang --top synth_top -G DUT="{run.dut}" {params} --best-effort-hierarchy '
        + " ".join(run.sources + ["fpga/synth/synth_top.sv"]),
        "hierarchy -top synth_top",
        # Keeping the DUT as its own module lets one synthesis report DUT and wrapper cells separately.
        f"setattr -mod -set keep_hierarchy 1 {run.dut}*",
        f"synth_ecp5 {synth_args} -run :map_luts",
        # LUT mapping drops internal register net names, so each FF cell is named after its register bit first.
        "rename -wire -suffix _reg t:TRELLIS_FF",
        f"synth_ecp5 {synth_args} -run map_luts:",
        f"tee -q -o {logs / 'stat.json'} stat -json",
        f"setattr -mod -unset keep_hierarchy {run.dut}*",
        "flatten",
        "stat",
        f"write_json {build / 'net.json'}",
    ])
    (build / "synth.ys").write_text(script + "\n")
    subprocess.run([tool("yosys"), "-m", "slang", "-q", "-l", logs / "yosys.log", "-s", build / "synth.ys"],
                   cwd=REPO, check=True, stdout=subprocess.DEVNULL)


def pnr(run, seed):
    logs = LOGS / run.slug
    subprocess.run([tool("nextpnr-ecp5"), *DEVICE, "--json", BUILD / run.slug / "net.json",
                    "--freq", str(TARGET_MHZ), "--seed", str(seed), "--timing-allow-fail",
                    "--report", logs / f"nextpnr_seed{seed}.json", "--log", logs / f"nextpnr_seed{seed}.log", "-q"],
                   check=True, stdout=subprocess.DEVNULL)


def cell_counts(cells_by_type):
    counts = {col: cells_by_type.get(cell, 0) for col, cell in CELLS.items()}
    other = {k: v for k, v in cells_by_type.items() if k not in CELLS.values() and not k.startswith(("mul_", "$"))}
    return counts, other


def resources(run):
    modules = json.loads((LOGS / run.slug / "stat.json").read_text())["modules"]
    dut = next(v for k, v in modules.items() if k.lstrip("\\").startswith(run.dut + "$"))
    return cell_counts(dut["num_cells_by_type"]), cell_counts(modules["\\synth_top"]["num_cells_by_type"])


def endpoint(pin):
    return f"{pin['cell'].removesuffix('_reg')}.{pin['port']}"


def timing(run):
    seeds = []
    for seed in SEEDS:
        report = json.loads((LOGS / run.slug / f"nextpnr_seed{seed}.json").read_text())
        (fmax,) = (clk["achieved"] for clk in report["fmax"].values())
        path = next(p for p in report["critical_paths"]
                    if p["from"].startswith("posedge") and p["to"].startswith("posedge"))["path"]
        seeds.append({"seed": seed, "fmax": fmax, "start": endpoint(path[0]["from"]), "end": endpoint(path[-1]["to"])})
    median = sorted(seeds, key=lambda s: s["fmax"])[len(seeds) // 2]
    return seeds, median


def latency_model(run):
    """Returns (latency label, latency cycles for ns, results per cycle) from the simulation results."""
    if not run.sim_cfg:
        return "1*", 1, 1.0
    stats_file = SIM_BUILD / run.sim_cfg / "stats.json"
    if not stats_file.exists():
        sys.exit(f"{stats_file} is missing. Run `python3 rtl/mul/tb/test_mul.py W64` first.")
    stats = json.loads(stats_file.read_text())
    lo, hi = stats["lat_min"], stats["lat_max"]
    label = str(hi) if lo == hi else f"{lo}..{hi}"
    if "sustained_throughput" in stats:
        return label, hi, stats["sustained_throughput"]
    return label, hi, 1 / (hi + 1)


def version(name, flag, pattern):
    out = subprocess.run([tool(name), flag], capture_output=True, text=True)
    return re.search(pattern, out.stdout + out.stderr).group(1)


def fmt_table(header, rows):
    lines = ["| " + " | ".join(header) + " |", "|" + "|".join("---" for _ in header) + "|"]
    lines += ["| " + " | ".join(str(c) for c in row) + " |" for row in rows]
    return "\n".join(lines)


def main(args):
    report_only = "--report-only" in args
    filters = [a for a in args if a != "--report-only"]
    runs = [r for r in RUNS if not filters or any(f in r.slug for f in filters)]
    if not report_only:
        with ThreadPoolExecutor(JOBS) as pool:
            list(pool.map(synth, runs))
        with ThreadPoolExecutor(JOBS) as pool:
            list(pool.map(lambda job: pnr(*job), [(r, s) for r in runs for s in SEEDS]))

    main_rows, seed_rows, wrap_rows, other_notes = [], [], [], []
    for run in runs:
        (dut, dut_other), (wrap, wrap_other) = resources(run)
        seeds, med = timing(run)
        lat_label, lat_cycles, per_cycle = latency_model(run)
        fmax = med["fmax"]
        thr = fmax * per_cycle
        main_rows.append([
            run.label, dut["LUTs"], dut["FFs"], dut["Carry"], dut["DSPs"], f"{fmax:.1f}",
            f"`{med['start']}`", f"`{med['end']}`", lat_label, f"{lat_cycles * 1000 / fmax:.1f}",
            f"{thr:.2f}", f"{thr / (dut['LUTs'] / 1000):.2f}",
        ])
        seed_rows.append([run.label] + [f"{s['fmax']:.1f}" for s in seeds] + [str(med["seed"])])
        wrap_rows.append([run.label, wrap["LUTs"], wrap["FFs"], wrap["Carry"], wrap["DSPs"]])
        for owner, other in (("DUT", dut_other), ("wrapper", wrap_other)):
            if other:
                other_notes.append(f"- {run.label} {owner} also uses " + ", ".join(f"{v} {k}" for k, v in other.items()) + ".")

    header = ["Run", "LUTs", "FFs", "Carry (CCU2C)", "DSPs (MULT18X18D)", "Median fmax (MHz)",
              "Critical path start", "Critical path end", "Latency (cycles)", "Latency (ns)",
              "Throughput (Mresults/s)", "Mresults/s per 1k LUTs"]
    table = fmt_table(header, main_rows)
    md = "\n\n".join([
        "# W=64 multiplier synthesis and place-and-route",
        "\n".join([
            f"- The target is an ECP5 LFE5U-85F in CABGA381 at speed grade 6, with a {TARGET_MHZ} MHz nextpnr target.",
            f"- The tools are Yosys {version('yosys', '-V', r'Yosys (\S+)')} with the slang frontend and "
            f"nextpnr-ecp5 {version('nextpnr-ecp5', '--version', r'Version nextpnr-(\S+?)\)')}.",
            f"- Each run places and routes with seeds {', '.join(map(str, SEEDS))}, and the table reports the median-fmax seed.",
            "- Resource columns count the DUT only. The wrapper cost is listed separately below.",
            "- Scripts are in fpga/synth/ and raw logs are in benchmarks/stage2/logs/.",
        ]),
        table,
        "\n".join([
            "- Latency cycles come from the cocotb runs in rtl/mul/tb (cycle start or in_valid is high to the cycle done or out_valid is high).",
            "- mul_iter_csa, mul_digit_serial and mul_digit_serial_pad issue one result every latency + 1 cycles, and mul_pipe issues one result per cycle.",
            "- mul_digit_serial_pad zero-extends b to a multiple of D bits so that D need not divide W. Its latency is ceil(W/D) + 2 cycles.",
            "- A latency range means the latency depends on the operands, and latency ns and throughput then use the worst case.",
            "- \\* A combinational DUT has no internal registers. Its result is captured on the next clock edge, so it costs one period, the same as mul_pipe STAGES=1.",
            "- Critical path endpoints are nextpnr's cell.pin names. The script names each FF cell after the register bit it drives so the names stay readable.",
            "- Mresults/s per 1k LUTs counts LUT4 cells only. It ignores carry cells and DSP blocks, which flatters the DSP run.",
        ] + other_notes),
        "## Fmax per seed (MHz)",
        fmt_table(["Run"] + [f"Seed {s}" for s in SEEDS] + ["Median seed"], seed_rows),
        "## Wrapper cost",
        "The wrapper has a 128-bit LFSR, registered DUT inputs and outputs, and a 3-level registered XOR tree. Subtract these cells from a full-design count to get the DUT cost.",
        fmt_table(["Run", "LUTs", "FFs", "Carry", "DSPs"], wrap_rows),
    ]) + "\n"
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "mul_synth.md").write_text(md)
    print(table)


if __name__ == "__main__":
    main(sys.argv[1:])
