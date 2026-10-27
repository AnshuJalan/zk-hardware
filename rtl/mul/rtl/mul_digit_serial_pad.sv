// Digit-serial W x W -> 2W unsigned multiplier that zero-extends b to a multiple of D bits so D need not divide W, and raises done exactly ceil(W/D) + 2 cycles after start.
module mul_digit_serial_pad #(
  parameter int W = 8,
  parameter int D = 5
) (
  input  logic           clk,
  input  logic           rst_n,
  input  logic           start,
  input  logic [W-1:0]   a,
  input  logic [W-1:0]   b,
  output logic           done,
  output logic [2*W-1:0] p
);
  if (D < 1) begin : gen_d_min_check
    $fatal(1, "mul_digit_serial_pad: D=%0d must be >= 1", D);
  end

  localparam int N     = (W + D - 1) / D;
  localparam int WP    = N * D;
  localparam int CNT_W = (N > 1) ? $clog2(N) : 1;

  typedef enum logic [1:0] { IDLE, RUN, ADD, DONE } mul_digit_serial_pad_st_e;
  mul_digit_serial_pad_st_e state_q, state_d;

  logic load, step, capture, last;

  // a_q and the accumulator stay 2W bits wide because the product fits in 2W bits.
  // The bits that the last step shifts out of a_q only meet padded zero bits of b.
  logic [2*W-1:0]   a_q, a_d;
  logic [WP-1:0]    b_q, b_d;
  logic [2*W-1:0]   s_q, s_d, c_q, c_d;
  logic [2*W-1:0]   p_q, p_d;
  logic [CNT_W-1:0] cnt_q, cnt_d;

  // The control FSM drives only the load, step and capture enables.
  always_ff @(posedge clk or negedge rst_n) begin
    if (~rst_n) state_q <= IDLE;
    else        state_q <= state_d;
  end

  always_comb begin
    state_d = state_q;
    load    = 1'b0;
    step    = 1'b0;
    capture = 1'b0;

    case (state_q)
      IDLE:
        if (start) begin
          load    = 1'b1;
          state_d = RUN;
        end
      RUN: begin
        step = 1'b1;
        if (last) state_d = ADD;
      end
      ADD: begin
        capture = 1'b1;
        state_d = DONE;
      end
      DONE:
        state_d = IDLE;
      default:
        state_d = IDLE;
    endcase
  end

  assign done = state_q == DONE;

  // The datapath registers change only under the FSM enables.
  // gen_acc[j] holds the carry-save pair after folding j partial products into
  // (s_q, c_q). Each link of the chain is a separate variable so that
  // simulators do not report a false combinational loop through one shared array.
  for (genvar j = 0; j <= D; j++) begin : gen_acc
    logic [2*W-1:0] s, c;

    if (j == 0) begin : gen_seed
      assign s = s_q;
      assign c = c_q;
    end
    else begin : gen_csa
      logic [2*W-1:0] pp;

      assign pp = (a_q << (j-1)) & {(2*W){b_q[j-1]}};

      csa_3_2 #(.W(2*W)) u_csa (
        .x(gen_acc[j-1].s),
        .y(gen_acc[j-1].c),
        .z(pp),
        .s(s),
        .c(c)
      );
    end
  end

  assign last = cnt_q == CNT_W'(N-1);

  always_comb begin
    a_d   = a_q;
    b_d   = b_q;
    s_d   = s_q;
    c_d   = c_q;
    p_d   = p_q;
    cnt_d = cnt_q;

    if (load) begin
      a_d   = (2*W)'(a);
      b_d   = WP'(b);
      s_d   = '0;
      c_d   = '0;
      cnt_d = '0;
    end
    else if (step) begin
      a_d   = a_q << D;
      b_d   = b_q >> D;
      s_d   = gen_acc[D].s;
      c_d   = gen_acc[D].c;
      cnt_d = cnt_q + CNT_W'(1);
    end

    if (capture) p_d = s_q + c_q;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      a_q   <= '0;
      b_q   <= '0;
      s_q   <= '0;
      c_q   <= '0;
      p_q   <= '0;
      cnt_q <= '0;
    end
    else begin
      a_q   <= a_d;
      b_q   <= b_d;
      s_q   <= s_d;
      c_q   <= c_d;
      p_q   <= p_d;
      cnt_q <= cnt_d;
    end
  end

  assign p = p_q;
endmodule
