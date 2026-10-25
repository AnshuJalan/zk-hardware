module add_mod_97 #(
  parameter int W = 7,
  parameter logic [W-1:0] P = 97
)(
  input logic [W-1:0] a,
  input logic [W-1:0] b,
  output logic [W-1:0] result
);
  logic [W:0] raw;
  logic [W+1:0] sub;

  assign raw    = a + b;
  assign sub    = {1'b0, raw} - P;
  assign result = sub[W+1] ? raw[W-1:0] : sub[W-1:0];
endmodule
