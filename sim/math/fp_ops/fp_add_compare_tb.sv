`default_nettype none

module fp_add_compare_tb (
  input wire clk,
  input fp a,
  input fp b,
  input wire is_sub,
  output fp sum_new,
  output fp sum_baseline
);
  fp_add dut_new (
    .clk(clk),
    .a(a),
    .b(b),
    .is_sub(is_sub),
    .sum(sum_new)
  );

  fp_add_baseline dut_baseline (
    .clk(clk),
    .a(a),
    .b(b),
    .is_sub(is_sub),
    .sum(sum_baseline)
  );
endmodule

`default_nettype wire
