// Behavioral W x W -> 2W unsigned multiplier that serves only as a baseline.
module mul_behav #(
  parameter int W = 8
) (
  input  logic [W-1:0]   a,
  input  logic [W-1:0]   b,
  output logic [2*W-1:0] p
);
  if (W < 1) begin : gen_w_check
    $fatal(1, "mul_behav: W=%0d must be >= 1", W);
  end

  assign p = a * b;
endmodule
