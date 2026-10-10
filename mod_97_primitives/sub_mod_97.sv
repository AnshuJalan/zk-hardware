module add_mod_97(
  input logic [6:0] a,
  input logic [6:0] b,
  output logic [6:0] result
);
  logic [7:0] raw; // MSB is used as sign bit

  assign raw    = {1'b0, a} - {1'b0, b};
  assign result = raw[7] ? raw + 8'd97 : raw;
endmodule