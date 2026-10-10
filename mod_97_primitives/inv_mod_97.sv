module inv_mod_97(
  input logic clk, 
  input logic rst,
  input logic [6:0] a,
  output logic valid,
  output logic inv_exist,
  output logic [6:0] result
);
  exp_mod_97 em97(
    .clk(clk),
    .rst(rst),
    .base(a),
    .exp(7'd95),
    .valid(valid),
    .result(result)
  );

  assign inv_exist = a != 7'd0;
endmodule