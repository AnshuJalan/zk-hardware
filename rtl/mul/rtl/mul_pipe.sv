// Pipelined W x W -> 2W unsigned multiplier that accepts one pair per cycle and returns its product with out_valid exactly STAGES cycles later.
module mul_pipe #(
  parameter int W      = 8,
  parameter int STAGES = 1
) (
  input  logic           clk,
  input  logic           rst_n,
  input  logic           in_valid,
  input  logic [W-1:0]   a,
  input  logic [W-1:0]   b,
  output logic           out_valid,
  output logic [2*W-1:0] p
);
  if (STAGES < 1) begin : gen_stages_min_check
    $fatal(1, "mul_pipe: STAGES=%0d must be >= 1", STAGES);
  end
  else if (W % STAGES != 0) begin : gen_stages_div_check
    $fatal(1, "mul_pipe: W=%0d must be divisible by STAGES=%0d", W, STAGES);
  end

  localparam int K = W / STAGES;

  // Index k holds the inputs of stage k. Index 0 is the module input and
  // index k > 0 is the register bank at the end of stage k-1.
  logic           st_v [STAGES];
  logic [2*W-1:0] st_s [STAGES];
  logic [2*W-1:0] st_c [STAGES];
  logic [2*W-1:0] st_a [STAGES];
  logic [W-1:0]   st_b [STAGES];

  logic           out_valid_q, out_valid_d;
  logic [2*W-1:0] p_q, p_d;

  assign st_v[0] = in_valid;
  assign st_s[0] = '0;
  assign st_c[0] = '0;
  assign st_a[0] = (2*W)'(a);
  assign st_b[0] = b;

  for (genvar k = 0; k < STAGES; k++) begin : gen_stage
    // gen_acc[j] holds the carry-save pair after folding j of this stage's
    // partial products. Each link of the chain is a separate variable so that
    // simulators do not report a false combinational loop through one shared array.
    for (genvar j = 0; j <= K; j++) begin : gen_acc
      logic [2*W-1:0] s, c;

      if (j == 0) begin : gen_seed
        assign s = st_s[k];
        assign c = st_c[k];
      end
      else begin : gen_csa
        logic [2*W-1:0] pp;

        assign pp = (st_a[k] << (j-1)) & {(2*W){st_b[k][j-1]}};

        csa_3_2 #(.W(2*W)) u_csa (
          .x(gen_acc[j-1].s),
          .y(gen_acc[j-1].c),
          .z(pp),
          .s(s),
          .c(c)
        );
      end
    end

    if (k < STAGES-1) begin : gen_reg
      logic           v_q, v_d;
      logic [2*W-1:0] s_q, s_d, c_q, c_d, a_q, a_d;
      logic [W-1:0]   b_q, b_d;

      always_comb begin
        v_d = st_v[k];
        s_d = gen_acc[K].s;
        c_d = gen_acc[K].c;
        a_d = st_a[k] << K;
        b_d = st_b[k] >> K;
      end

      always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
          v_q <= 1'b0;
          s_q <= '0;
          c_q <= '0;
          a_q <= '0;
          b_q <= '0;
        end
        else begin
          v_q <= v_d;
          s_q <= s_d;
          c_q <= c_d;
          a_q <= a_d;
          b_q <= b_d;
        end
      end

      assign st_v[k+1] = v_q;
      assign st_s[k+1] = s_q;
      assign st_c[k+1] = c_q;
      assign st_a[k+1] = a_q;
      assign st_b[k+1] = b_q;
    end
    else begin : gen_out
      always_comb begin
        out_valid_d = st_v[k];
        p_d         = gen_acc[K].s + gen_acc[K].c;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      out_valid_q <= 1'b0;
      p_q         <= '0;
    end
    else begin
      out_valid_q <= out_valid_d;
      p_q         <= p_d;
    end
  end

  assign out_valid = out_valid_q;
  assign p         = p_q;
endmodule
