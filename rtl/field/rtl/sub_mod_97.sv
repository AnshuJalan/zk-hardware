module sub_mod_97 #(
  parameter int W = 7,
  parameter logic [W-1:0] P = 97
)(
  input logic [W-1:0] a,
  input logic [W-1:0] b,
  output logic [W-1:0] result
);
  logic [W:0] raw; // MSB is used as sign bit
  logic [W:0] wrapped;

  assign raw     = {1'b0, a} - {1'b0, b};
  assign wrapped = raw + P;
  assign result  = raw[W] ? wrapped[W-1:0] : raw[W-1:0];
endmodule
