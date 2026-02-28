`default_nettype wire

/*
  fp_sqrt:
    find square root of an fp by doing x / sqrt(x)

  timing:
    INV_SQRT_DELAY + fp_mul delay (1)
*/

module fp_sqrt (
  input wire clk,
  input wire rst,

  input fp x,
  output fp sqrt
);
  localparam integer SQRT_PIPE_DELAY = INV_SQRT_DELAY;

  fp x_inv_sqrt;
  fp x_piped;
  
  pipeline #(.WIDTH(FP_BITS), .DEPTH(SQRT_PIPE_DELAY)) x_pipe (.clk(clk), .in(x), .out(x_piped));

  fp_inv_sqrt inv_sqrt_x_isq(
    .clk(clk),
    .rst(rst),
    .x(x),
    .x_valid(1'b1),
    .inv_sqrt(x_inv_sqrt),
    .inv_sqrt_valid()
  );
  fp_mul mul_sqrt(.clk(clk), .rst(rst), .a(x_piped), .b(x_inv_sqrt), .prod(sqrt));

endmodule

`default_nettype none
