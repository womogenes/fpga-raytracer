`default_nettype none

module fp_sqrt_fast (
  input wire clk,
  input wire rst,
  input fp x,
  output fp sqrt
);
  localparam integer INV_SQRT_FAST_DELAY = INV_SQRT_NR_STAGES * 4;

  fp x_inv_sqrt;
  fp x_piped;

  pipeline #(.WIDTH(FP_BITS), .DEPTH(INV_SQRT_FAST_DELAY)) x_pipe (.clk(clk), .in(x), .out(x_piped));
  fp_inv_sqrt_fast inv_sqrt_x(.clk(clk), .rst(rst), .x(x), .x_valid(1'b1), .inv_sqrt(x_inv_sqrt), .inv_sqrt_valid());
  fp_mul mul_sqrt(.clk(clk), .rst(rst), .a(x_piped), .b(x_inv_sqrt), .prod(sqrt));
endmodule

`default_nettype wire
