module mul_mod_97 #(
  parameter int W = 7,
  parameter logic [W-1:0] P = 97
)(
  input logic [W-1:0] a,
  input logic [W-1:0] b,
  output logic [W-1:0] result
);
  // Barrett reduction: meu = floor(2^(2W) / p)
  localparam logic [2*W:0] R   = {1'b1, {(2*W){1'b0}}};
  localparam logic [2*W:0] MEU = R / P;

  logic [2*W-1:0] x;
  logic [4*W:0] x_meu;
  logic [W:0] q;
  logic [W:0] res;

  always_comb begin
    x     = a * b;
    x_meu = x * MEU;
    q     = x_meu[2*W+W:2*W];
    res   = (W+1)'(x - (q * P));
    if (res >= P) res = res - P;
  end

  assign result = res[W-1:0];
endmodule
