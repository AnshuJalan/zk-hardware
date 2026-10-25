# ZK Hadrware

This repo is a learning lab for ZK hardware, starting with parameterized field-arithmetic RTL in SystemVerilog.

## Layout

- `rtl/common/` holds shared primitives such as the 3:2 carry-save adder.
- `rtl/mul/` holds the multiplier variants in `rtl/` and their cocotb tests in `tb/`.
- `rtl/field/` holds the field arithmetic units.
- `reference/` holds the Python golden models.

## Tests

The multiplier tests need cocotb and Verilator.

```
python3 rtl/mul/tb/test_mul.py           # runs every configuration and prints a summary table
python3 rtl/mul/tb/test_mul.py mul_pipe  # runs only the configurations whose name matches
```

## Handwritten files

These files are written by hand.

- [rtl/field/rtl/add_mod_97.sv](rtl/field/rtl/add_mod_97.sv)
- [rtl/field/rtl/sub_mod_97.sv](rtl/field/rtl/sub_mod_97.sv)
- [rtl/field/rtl/mul_mod_97.sv](rtl/field/rtl/mul_mod_97.sv)
- [rtl/field/rtl/exp_mod_97.sv](rtl/field/rtl/exp_mod_97.sv)
- [rtl/field/rtl/inv_mod_97.sv](rtl/field/rtl/inv_mod_97.sv)
- [rtl/mul/rtl/mul_iter_csa.sv](rtl/mul/rtl/mul_iter_csa.sv)
