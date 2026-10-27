// Timing wrapper that feeds one multiplier from an LFSR and folds its outputs to a few pins so every DUT path is flop to flop.
module synth_top #(
  parameter string DUT    = "mul_comb",
  parameter int    W      = 64,
  parameter int    D      = 4,
  parameter int    STAGES = 4,
  localparam int   N0     = 2*W + 1,
  localparam int   N1     = (N0 + 3) / 4,
  localparam int   N2     = (N1 + 3) / 4,
  localparam int   NOUT   = (N2 + 3) / 4
) (
  input  logic            clk,
  input  logic            rst_n,
  output logic [NOUT-1:0] out
);
  if (W < 2 || W > 64) begin : gen_w_check
    $fatal(1, "synth_top: W=%0d must be in 2..64", W);
  end

  // The 128-bit maximal-length LFSR uses taps 128, 126, 101 and 99.
  logic [127:0] lfsr_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (~rst_n) lfsr_q <= 128'h0123_4567_89ab_cdef_fedc_ba98_7654_3210;
    else        lfsr_q <= {lfsr_q[126:0], lfsr_q[127] ^ lfsr_q[125] ^ lfsr_q[100] ^ lfsr_q[98]};
  end

  // The DUT boundary registers have no reset so that yosys cannot merge them
  // into the LFSR flops, which share their D inputs.
  (* keep *) logic [W-1:0]   a_q, b_q;
  (* keep *) logic           go_q;
  (* keep *) logic [2*W-1:0] dut_p;
  (* keep *) logic           dut_flag;
  (* keep *) logic [2*W-1:0] p_q;
  (* keep *) logic           flag_q;

  always_ff @(posedge clk) begin
    a_q    <= lfsr_q[W-1:0];
    b_q    <= lfsr_q[64 +: W];
    go_q   <= lfsr_q[127];
    p_q    <= dut_p;
    flag_q <= dut_flag;
  end

  if (DUT == "mul_comb") begin : gen_dut
    mul_comb #(.W(W)) u_dut (.a(a_q), .b(b_q), .p(dut_p));
    assign dut_flag = 1'b0;
  end
  else if (DUT == "mul_behav") begin : gen_dut
    mul_behav #(.W(W)) u_dut (.a(a_q), .b(b_q), .p(dut_p));
    assign dut_flag = 1'b0;
  end
  else if (DUT == "mul_iter_csa") begin : gen_dut
    mul_iter_csa #(.W(W)) u_dut (
      .clk, .rst_n, .start(go_q), .a(a_q), .b(b_q), .done(dut_flag), .p(dut_p)
    );
  end
  else if (DUT == "mul_digit_serial") begin : gen_dut
    mul_digit_serial #(.W(W), .D(D)) u_dut (
      .clk, .rst_n, .start(go_q), .a(a_q), .b(b_q), .done(dut_flag), .p(dut_p)
    );
  end
  else if (DUT == "mul_digit_serial_pad") begin : gen_dut
    mul_digit_serial_pad #(.W(W), .D(D)) u_dut (
      .clk, .rst_n, .start(go_q), .a(a_q), .b(b_q), .done(dut_flag), .p(dut_p)
    );
  end
  else if (DUT == "mul_pipe") begin : gen_dut
    mul_pipe #(.W(W), .STAGES(STAGES)) u_dut (
      .clk, .rst_n, .in_valid(go_q), .a(a_q), .b(b_q), .out_valid(dut_flag), .p(dut_p)
    );
  end
  else begin : gen_dut
    $fatal(1, "synth_top: unknown DUT %s", DUT);
  end

  // The registered XOR tree folds 4 bits per LUT per level down to NOUT pins.
  logic [4*N1-1:0]   l0;
  logic [N1-1:0]     l1_q;
  logic [4*N2-1:0]   l1;
  logic [N2-1:0]     l2_q;
  logic [4*NOUT-1:0] l2;
  logic [NOUT-1:0]   l3_q;

  assign l0 = (4*N1)'({flag_q, p_q});
  assign l1 = (4*N2)'(l1_q);
  assign l2 = (4*NOUT)'(l2_q);

  always_ff @(posedge clk) begin
    for (int i = 0; i < N1; i++)   l1_q[i] <= ^l0[4*i +: 4];
    for (int i = 0; i < N2; i++)   l2_q[i] <= ^l1[4*i +: 4];
    for (int i = 0; i < NOUT; i++) l3_q[i] <= ^l2[4*i +: 4];
  end

  assign out = l3_q;
endmodule
