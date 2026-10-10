module exp_mod_97(
  input logic clk,
  input logic rst,
  input logic [6:0] base,
  input logic [6:0] exp, 
  output logic valid,
  output logic [6:0] result
);
  // Operands and accumulator
  logic [6:0] exp_curr, exp_next;
  logic [6:0] base_curr, base_next;
  logic [6:0] res_curr, res_next;

  // Multiplier signals
  logic [6:0] mul_inp_a_curr, mul_inp_a_next;
  logic [6:0] mul_inp_b_curr, mul_inp_b_next;
  logic [6:0] mul_result;

  // State of the multiplier
  typedef enum logic [1:0] { SQUARE, ACCUMULATE, IDLE, DONE } mul_state_type;
  mul_state_type mul_state, mul_state_next;

  mul_mod_97 mm97(
    .a(mul_inp_a_curr),
    .b(mul_inp_b_curr),
    .result(mul_result)
  );

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      exp_curr <= exp;
      base_curr <= base;
      res_curr <= 7'd1;
      mul_inp_a_curr <= 7'b0;
      mul_inp_b_curr <= 7'b0;
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
          exp_next = {1'b0, exp_curr[5:0]}; // Right shift
          mul_state_next = ~|exp_next ? DONE : IDLE;
        end
      DONE: mul_state_next = DONE;
      default: mul_state_next = IDLE;
    endcase
  end

  assign valid = mul_state == DONE;
  assign result = res_curr;
endmodule