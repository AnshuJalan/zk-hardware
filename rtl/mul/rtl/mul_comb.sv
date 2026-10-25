// Combinational W x W -> 2W unsigned multiplier that reduces W AND-gate partial products through a chain of W-2 CSAs and one final add.
module mul_comb #(
  parameter int W = 8
) (
  input  logic [W-1:0]   a,
  input  logic [W-1:0]   b,
  output logic [2*W-1:0] p
);
  if (W < 2) begin : gen_w_check
    $fatal(1, "mul_comb: W=%0d must be >= 2", W);
  end

  logic [2*W-1:0] pp [W];

  for (genvar i = 0; i < W; i++) begin : gen_pp
    assign pp[i] = (2*W)'(a & {W{b[i]}}) << i;
  end

  // Each link of the chain is a separate variable so that simulators do not
  // report a false combinational loop through one shared array.
  for (genvar i = 1; i < W; i++) begin : gen_acc
    logic [2*W-1:0] s, c;

    if (i == 1) begin : gen_seed
      assign s = pp[0];
      assign c = pp[1];
    end
    else begin : gen_csa
      csa_3_2 #(.W(2*W)) u_csa (
        .x(gen_acc[i-1].s),
        .y(gen_acc[i-1].c),
        .z(pp[i]),
        .s(s),
        .c(c)
      );
    end
  end

  assign p = gen_acc[W-1].s + gen_acc[W-1].c;
endmodule
