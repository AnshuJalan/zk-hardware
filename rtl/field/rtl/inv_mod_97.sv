module inv_mod_97 #(
  parameter int W = 7,
  parameter logic [W-1:0] P = 97
)(
  input logic clk, 
  input logic rst,
  input logic [W-1:0] a,
  output logic valid,
  output logic inv_exist,
  output logic [W-1:0] result
);
  // Fermat's little theorem: a^-1 = a^(p-2) mod p
  localparam logic [W-1:0] EXP = P - 2;

  exp_mod_97 #(.W(W), .P(P)) em97(
    .clk(clk),
    .rst(rst),
    .base(a),
    .exp(EXP),
    .valid(valid),
    .result(result)
  );

  assign inv_exist = a != '0;
endmodule
