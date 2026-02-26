`default_nettype none

module fp_inv_sqrt_compare_tb (
  input wire clk,
  input wire rst,
  input fp x,
  input wire x_valid,
  output fp inv_sqrt_new,
  output wire inv_sqrt_valid_new,
  output fp inv_sqrt_baseline,
  output wire inv_sqrt_valid_baseline
);
  fp_inv_sqrt dut_new (
    .clk(clk),
    .rst(rst),
    .x(x),
    .x_valid(x_valid),
    .inv_sqrt(inv_sqrt_new),
    .inv_sqrt_valid(inv_sqrt_valid_new)
  );

  fp_inv_sqrt_baseline dut_baseline (
    .clk(clk),
    .rst(rst),
    .x(x),
    .x_valid(x_valid),
    .inv_sqrt(inv_sqrt_baseline),
    .inv_sqrt_valid(inv_sqrt_valid_baseline)
  );
endmodule

`default_nettype wire
