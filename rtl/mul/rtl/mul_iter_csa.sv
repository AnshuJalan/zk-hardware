module mul_iter_csa #(
  parameter int W = 8
) (
  input  logic           clk,
  input  logic           rst_n,   
  input  logic           start,   
  input  logic [W-1:0]   a,
  input  logic [W-1:0]   b,
  output logic           done,
  output logic [2*W-1:0] p
);
  if (W < 2) begin : gen_w_check
    $fatal(1, "mul_iter_csa: W=%0d must be >= 2", W);
  end

  localparam int CNT_W = $clog2(W+1);

  // Registers
  logic [2*W-1:0] a_q, a_d, b_q, b_d;
  logic [2*W-1:0] s_q, s_d, c_q, c_d;
  logic [2*W-1:0] p_q, p_d;
  logic [CNT_W-1:0] cnt_q, cnt_d;

  logic [2*W-1:0] pp, csa_sum, csa_carry, final_sum, a_shl, b_shr;

  typedef enum logic [1:0] { IDLE, RUN, DONE } mul_iter_csa_st_e;
  mul_iter_csa_st_e state_q, state_d;

  always_ff @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      state_q <= IDLE;
      c_q <= (2*W)'(0);
      s_q <= (2*W)'(0);
      a_q <= (2*W)'(0);
      b_q <= (2*W)'(0);
      p_q <= (2*W)'(0);
      cnt_q <= CNT_W'(0);
    end
    else begin
      state_q <= state_d;
      c_q <= c_d;
      s_q <= s_d;
      a_q <= a_d;
      b_q <= b_d;
      p_q <= p_d;
      cnt_q <= cnt_d;
    end
  end

  always_comb begin
    state_d = state_q;
    c_d = c_q;
    s_d = s_q;
    a_d = a_q;
    b_d = b_q;
    p_d = p_q;
    cnt_d = cnt_q;

    case (state_q)
      IDLE: 
        begin
          if (start) begin
            state_d = RUN;
            a_d = {W'(0), a};
            b_d = {W'(0), b};
            s_d = (2*W)'(0);
            c_d = (2*W)'(0);
            cnt_d = CNT_W'(0);
          end
          else state_d = IDLE;
        end
      RUN:
        if (cnt_q == CNT_W'(W)) begin
          state_d = DONE;
          p_d = final_sum;
        end
        else begin
          c_d = csa_carry;
          s_d = csa_sum;
          a_d = a_shl;
          b_d = b_shr;
          state_d = RUN;
          cnt_d = cnt_q + CNT_W'(1);
        end
      DONE:
        state_d = IDLE;
      default:
        state_d = IDLE;
    endcase
  end

  assign pp = (a_q & {(2*W){b_q[0]}});
  assign csa_sum = pp ^ s_q ^ c_q;
  assign csa_carry = ((pp & s_q) | (s_q & c_q) | (pp & c_q)) << 1;
  assign final_sum = s_q + c_q;
  assign a_shl = a_q << 1;
  assign b_shr = b_q >> 1;

  assign done = state_q == DONE;
  assign p = p_q;
endmodule
