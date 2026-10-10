module mul_mod_97(
  input logic [6:0] a,
  input logic [6:0] b,
  output logic [6:0] result
);
  localparam int meu = 168; // floor(2^14 / p)

  logic [13:0] x;
  logic [21:0] x_meu;
  logic [7:0] q;
  logic [7:0] res;

  always_comb begin
    x     = a * b;
    x_meu = x * meu;
    q     = x_meu[21:14];
    res   = x - (q * 97);
    if (res >= 97) res = res - 97;
  end

  assign result = res;
endmodule