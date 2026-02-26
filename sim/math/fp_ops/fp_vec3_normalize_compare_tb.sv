`default_nettype none

module fp_vec3_normalize_compare_tb (
  input wire clk,
  input wire rst,
  input fp_vec3 v,
  output fp_vec3 normed_new,
  output fp_vec3 normed_baseline
);
  fp_vec3_normalize dut_new (
    .clk(clk),
    .rst(rst),
    .v(v),
    .normed(normed_new)
  );

  fp_vec3_normalize_baseline dut_baseline (
    .clk(clk),
    .rst(rst),
    .v(v),
    .normed(normed_baseline)
  );
endmodule

`default_nettype wire
