// 3:2 carry-save adder that turns x, y and z into a sum s and a pre-shifted carry c with s + c == x + y + z (mod 2^W).
module csa_3_2 #(
  parameter int W = 8
) (
  input  logic [W-1:0] x,
  input  logic [W-1:0] y,
  input  logic [W-1:0] z,
  output logic [W-1:0] s,
  output logic [W-1:0] c
);
  if (W < 1) begin : gen_w_check
    $fatal(1, "csa_3_2: W=%0d must be >= 1", W);
  end

  logic [W-1:0] maj;

  assign s   = x ^ y ^ z;
  assign maj = (x & y) | (y & z) | (x & z);
  assign c   = maj << 1;
endmodule
