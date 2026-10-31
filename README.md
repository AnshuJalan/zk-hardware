# ZK Hadrware

This repo is a learning lab for ZK hardware, starting with parameterized field-arithmetic RTL in SystemVerilog.

## Layout

- `rtl/common/` holds shared primitives such as the 3:2 carry-save adder.
- `rtl/mul/` holds the multiplier variants in `rtl/` and their cocotb tests in `tb/`.
- `rtl/field/` holds the field arithmetic units.
- `reference/` holds the Python golden models.

## Toolchain

The versions below are the ones the repo was last tested with.

| Tool | Tested version | Used for |
|---|---|---|
| Python 3 | 3.13.0 | The test runner, the golden models and the synthesis script |
| cocotb | 2.0.1 | The testbenches and the `cocotb_tools` runner |
| pytest | 9.1.1 | The pytest entry point of `test_mul.py`, which imports it |
| Verilator | 5.048 | RTL simulation |
| C++ compiler and make | Apple clang 21.0.0, GNU Make 3.81 | Building the Verilator models |
| Yosys with the slang plugin | 0.70+219 | Synthesis through `yosys -m slang` |
| nextpnr-ecp5 | 0.11.1-79-g22c5adf4 | Place and route on the ECP5 LFE5U-85F |

- `pip install cocotb pytest` installs the Python packages.
- [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build) ships Yosys with the slang plugin and nextpnr-ecp5. Set `OSS_CAD_SUITE` to its folder or put its `bin/` on PATH.
- On macOS, Apple clang may fail to find the libc++ headers with `'cstdint' file not found`. Setting `CPLUS_INCLUDE_PATH=$(xcrun --show-sdk-path)/usr/include/c++/v1` fixes the Verilator build.

## Tests

```
python3 rtl/mul/tb/test_mul.py           # runs every configuration and prints a summary table
python3 rtl/mul/tb/test_mul.py mul_pipe  # runs only the configurations whose name matches
```

## Synthesis benchmark

```
python3 rtl/mul/tb/test_mul.py W64                                  # produces the latency stats that run_synth.py reads
OSS_CAD_SUITE=<path> python3 fpga/synth/run_synth.py                # runs every design and writes benchmarks/stage2/mul_synth.md
OSS_CAD_SUITE=<path> python3 fpga/synth/run_synth.py pipe_s16       # runs only the designs whose slug matches
OSS_CAD_SUITE=<path> python3 fpga/synth/run_synth.py --report-only  # rebuilds the report from the existing logs
```

- A filtered run rewrites the report with only its own rows, so finish with `--report-only` to restore the full table.
- `SYNTH_JOBS` sets how many yosys and nextpnr jobs run in parallel. The default is 6.

## Handwritten files

These files are written by hand.

- [rtl/field/rtl/add_mod_97.sv](rtl/field/rtl/add_mod_97.sv)
- [rtl/field/rtl/sub_mod_97.sv](rtl/field/rtl/sub_mod_97.sv)
- [rtl/field/rtl/mul_mod_97.sv](rtl/field/rtl/mul_mod_97.sv)
- [rtl/field/rtl/exp_mod_97.sv](rtl/field/rtl/exp_mod_97.sv)
- [rtl/field/rtl/inv_mod_97.sv](rtl/field/rtl/inv_mod_97.sv)
- [rtl/mul/rtl/mul_iter_csa.sv](rtl/mul/rtl/mul_iter_csa.sv)
