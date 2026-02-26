`default_nettype none

module fp_vec3_dot_compare_tb (
  input wire clk,
  input wire rst,
  input fp_vec3 v,
  input fp_vec3 w,
  output fp dot_new,
  output fp dot_baseline
);
  fp_vec3_dot dut_new (
    .clk(clk),
    .rst(rst),
    .v(v),
    .w(w),
    .dot(dot_new)
  );

  fp_vec3_dot_baseline dut_baseline (
    .clk(clk),
    .rst(rst),
    .v(v),
    .w(w),
    .dot(dot_baseline)
  );
endmodule

`default_nettype wire
