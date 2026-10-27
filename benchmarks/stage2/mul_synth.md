# W=64 multiplier synthesis and place-and-route

- The target is an ECP5 LFE5U-85F in CABGA381 at speed grade 6, with a 200 MHz nextpnr target.
- The tools are Yosys 0.70+219 with the slang frontend and nextpnr-ecp5 0.11.1-79-g22c5adf4.
- Each run places and routes with seeds 1, 2, 3, and the table reports the median-fmax seed.
- Resource columns count the DUT only. The wrapper cost is listed separately below.
- Scripts are in fpga/synth/ and raw logs are in benchmarks/stage2/logs/.

| Run | LUTs | FFs | Carry (CCU2C) | DSPs (MULT18X18D) | Median fmax (MHz) | Critical path start | Critical path end | Latency (cycles) | Latency (ns) | Throughput (Mresults/s) | Mresults/s per 1k LUTs |
|---|---|---|---|---|---|---|---|---|---|---|---|
| mul_iter_csa | 590 | 585 | 68 | 0 | 138.6 | `gen_dut.u_dut.s_q[3].Q` | `gen_dut.u_dut.p_q[127].DI` | 66 | 476.1 | 2.07 | 3.51 |
| mul_digit_serial D=4 | 1828 | 580 | 62 | 0 | 137.2 | `gen_dut.u_dut.s_q[12].Q` | `gen_dut.u_dut.p_q[126].DI` | 18 | 131.2 | 7.22 | 3.95 |
| mul_digit_serial D=8 | 5654 | 575 | 60 | 0 | 85.1 | `gen_dut.u_dut.b_q[0].Q` | `gen_dut.u_dut.c_q[81].M` | 10 | 117.6 | 7.73 | 1.37 |
| mul_digit_serial_pad D=5 | 1963 | 579 | 62 | 0 | 130.6 | `gen_dut.u_dut.b_q[0].Q` | `gen_dut.u_dut.c_q[10].M` | 15 | 114.9 | 8.16 | 4.16 |
| mul_digit_serial_pad D=6 | 3176 | 578 | 61 | 0 | 115.8 | `gen_dut.u_dut.a_q[38].Q` | `gen_dut.u_dut.s_q[41].M` | 13 | 112.2 | 8.27 | 2.60 |
| mul_comb | 24455 | 0 | 33 | 0 | 15.1 | `b_q[0].Q` | `p_q[127].DI` | 1* | 66.4 | 15.06 | 0.62 |
| mul_pipe STAGES=4 | 14199 | 894 | 32 | 0 | 41.0 | `gen_dut.u_dut.gen_stage[2].gen_reg.b_q[0].Q` | `gen_dut.u_dut.p_q[127].DI` | 4 | 97.5 | 41.02 | 2.89 |
| mul_pipe STAGES=8 | 10230 | 1914 | 32 | 0 | 67.0 | `gen_dut.u_dut.gen_stage[6].gen_reg.b_q[0].Q` | `gen_dut.u_dut.p_q[127].DI` | 8 | 119.4 | 67.02 | 6.55 |
| mul_pipe STAGES=16 | 9870 | 3954 | 32 | 0 | 98.1 | `gen_dut.u_dut.gen_stage[14].gen_reg.b_q[0].Q` | `gen_dut.u_dut.p_q[127].DI` | 16 | 163.2 | 98.06 | 9.93 |
| mul_behav (-nodsp) | 16640 | 0 | 64 | 0 | 44.4 | `b_q[23].Q` | `p_q[127].DI` | 1* | 22.5 | 44.38 | 2.67 |
| mul_behav (DSP) | 716 | 0 | 224 | 16 | 54.3 | `a_q[31].Q` | `p_q[127].DI` | 1* | 18.4 | 54.32 | 75.87 |

- Latency cycles come from the cocotb runs in rtl/mul/tb (cycle start or in_valid is high to the cycle done or out_valid is high).
- mul_iter_csa, mul_digit_serial and mul_digit_serial_pad issue one result every latency + 1 cycles, and mul_pipe issues one result per cycle.
- mul_digit_serial_pad zero-extends b to a multiple of D bits so that D need not divide W. Its latency is ceil(W/D) + 2 cycles.
- A latency range means the latency depends on the operands, and latency ns and throughput then use the worst case.
- \* A combinational DUT has no internal registers. Its result is captured on the next clock edge, so it costs one period, the same as mul_pipe STAGES=1.
- Critical path endpoints are nextpnr's cell.pin names. The script names each FF cell after the register bit it drives so the names stay readable.
- Mresults/s per 1k LUTs counts LUT4 cells only. It ignores carry cells and DSP blocks, which flatters the DSP run.
- mul_iter_csa DUT also uses 5 PFUMX.
- mul_digit_serial D=4 DUT also uses 488 PFUMX.
- mul_digit_serial D=8 DUT also uses 1004 L6MUX21, 1872 PFUMX.
- mul_digit_serial_pad D=5 DUT also uses 21 PFUMX.
- mul_digit_serial_pad D=6 DUT also uses 245 L6MUX21, 629 PFUMX.
- mul_comb DUT also uses 5576 L6MUX21, 9063 PFUMX.
- mul_pipe STAGES=4 DUT also uses 1359 L6MUX21, 3126 PFUMX.
- mul_pipe STAGES=8 DUT also uses 202 L6MUX21, 745 PFUMX.
- mul_pipe STAGES=16 DUT also uses 115 L6MUX21, 298 PFUMX.
- mul_behav (-nodsp) DUT also uses 1933 L6MUX21, 4660 PFUMX.
- mul_behav (DSP) DUT also uses 202 L6MUX21, 294 PFUMX.

## Fmax per seed (MHz)

| Run | Seed 1 | Seed 2 | Seed 3 | Median seed |
|---|---|---|---|---|
| mul_iter_csa | 139.8 | 138.6 | 138.1 | 2 |
| mul_digit_serial D=4 | 137.2 | 137.9 | 134.4 | 1 |
| mul_digit_serial D=8 | 87.9 | 84.5 | 85.1 | 3 |
| mul_digit_serial_pad D=5 | 130.6 | 129.8 | 132.5 | 1 |
| mul_digit_serial_pad D=6 | 113.7 | 115.8 | 117.2 | 2 |
| mul_comb | 15.3 | 13.6 | 15.1 | 3 |
| mul_pipe STAGES=4 | 42.9 | 40.4 | 41.0 | 3 |
| mul_pipe STAGES=8 | 67.0 | 67.2 | 66.8 | 1 |
| mul_pipe STAGES=16 | 98.1 | 95.4 | 102.1 | 1 |
| mul_behav (-nodsp) | 44.8 | 40.8 | 44.4 | 3 |
| mul_behav (DSP) | 54.3 | 54.5 | 49.4 | 1 |

## Wrapper cost

The wrapper has a 128-bit LFSR, registered DUT inputs and outputs, and a 3-level registered XOR tree. Subtract these cells from a full-design count to get the DUT cost.

| Run | LUTs | FFs | Carry | DSPs |
|---|---|---|---|---|
| mul_iter_csa | 44 | 430 | 0 | 0 |
| mul_digit_serial D=4 | 44 | 430 | 0 | 0 |
| mul_digit_serial D=8 | 44 | 430 | 0 | 0 |
| mul_digit_serial_pad D=5 | 44 | 430 | 0 | 0 |
| mul_digit_serial_pad D=6 | 44 | 430 | 0 | 0 |
| mul_comb | 44 | 426 | 0 | 0 |
| mul_pipe STAGES=4 | 44 | 430 | 0 | 0 |
| mul_pipe STAGES=8 | 44 | 430 | 0 | 0 |
| mul_pipe STAGES=16 | 44 | 430 | 0 | 0 |
| mul_behav (-nodsp) | 44 | 426 | 0 | 0 |
| mul_behav (DSP) | 44 | 426 | 0 | 0 |
