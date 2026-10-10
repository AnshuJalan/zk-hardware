module add_mod_97(
  input logic [6:0] a,
  input logic [6:0] b,
  output logic [6:0] result
);
  logic [7:0] raw;
  logic [8:0] sub;

  assign raw    = a + b;
  assign sub    = {1'b0, raw} - 9'd97;
  assign result = sub[8] ? raw : sub;
endmodule