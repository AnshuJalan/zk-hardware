module exp_mod_97 #(
  parameter int W = 7,
  parameter logic [W-1:0] P = 97
)(
  input logic clk,
  input logic rst,
  input logic [W-1:0] base,
  input logic [W-1:0] exp, 
  output logic valid,
  output logic [W-1:0] result
);
  // Operands and accumulator
  logic [W-1:0] exp_curr, exp_next;
  logic [W-1:0] base_curr, base_next;
  logic [W-1:0] res_curr, res_next;

  // Multiplier signals
  logic [W-1:0] mul_inp_a_curr, mul_inp_a_next;
  logic [W-1:0] mul_inp_b_curr, mul_inp_b_next;
  logic [W-1:0] mul_result;

  // State of the multiplier
  typedef enum logic [1:0] { SQUARE, ACCUMULATE, IDLE, DONE } mul_state_type;
  mul_state_type mul_state, mul_state_next;

  mul_mod_97 #(.W(W), .P(P)) mm97(
    .a(mul_inp_a_curr),
    .b(mul_inp_b_curr),
    .result(mul_result)
  );

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      exp_curr <= exp;
      base_curr <= base;
      res_curr <= W'(1);
      mul_inp_a_curr <= '0;
      mul_inp_b_curr <= '0;
      mul_state <= IDLE;
    end else begin
      exp_curr <= exp_next;
      base_curr <= base_next;
      res_curr <= res_next;
      mul_inp_a_curr <= mul_inp_a_next;
      mul_inp_b_curr <= mul_inp_b_next;
      mul_state <= mul_state_next;
    end 
  end

  always_comb begin
    exp_next = exp_curr;
    base_next = base_curr;
    res_next = res_curr;
    mul_inp_a_next = mul_inp_a_curr;
    mul_inp_b_next = mul_inp_b_curr;
    mul_state_next = mul_state;

    case (mul_state)
      IDLE: 
        begin
          if (exp_curr[0]) begin
            mul_inp_a_next = res_curr;
            mul_inp_b_next = base_curr;
            mul_state_next = ACCUMULATE;
          end else begin
            mul_inp_a_next = base_curr;
            mul_inp_b_next = base_curr;
            mul_state_next = SQUARE;
          end
        end
      ACCUMULATE:
        begin
          res_next = mul_result;
          mul_inp_a_next = base_curr;
          mul_inp_b_next = base_curr;
          mul_state_next = SQUARE;
        end
      SQUARE:
        begin
          base_next = mul_result;
          exp_next = exp_curr >> 1;
          if (exp_next == '0) mul_state_next = DONE;
          else mul_state_next = IDLE;
        end
      DONE: mul_state_next = DONE;
      default: mul_state_next = IDLE;
    endcase
  end

  assign valid = mul_state == DONE;
  assign result = res_curr;
endmodule
