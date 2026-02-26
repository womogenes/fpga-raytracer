`default_nettype wire

/*
  fp_inv_stage:
    iteratively improve guess for 1/x, using y as starting guess

  timing:
    3 cycle delay
*/
module fp_inv_stage (
  input wire clk,
  input wire rst,

  input fp x,
  input fp y,
  // No valid signals :)

  output fp x_out,
  output fp y_next
);
  // Iteration step is y * (2 - x * y)
  // https://marc-b-reynolds.github.io/math/2017/09/18/ModInverse.html
  localparam fp two = FP_TWO;

  fp y_piped3;

  pipeline #(.WIDTH(FP_BITS), .DEPTH(3)) x_pipe (.clk(clk), .in(x), .out(x_out));
  pipeline #(.WIDTH(FP_BITS), .DEPTH(2)) y_pipe (.clk(clk), .in(y), .out(y_piped3));

  fp x_by_y;
  fp two_minus_xby;

  fp_mul mul_x_by_y(.clk(clk), .a(x), .b(y), .prod(x_by_y));
  fp_add add_two_minus_xby(.clk(clk), .a(two), .b(x_by_y), .is_sub(1'b1), .sum(two_minus_xby));
  fp_mul mul_y_next(.clk(clk), .a(y_piped3), .b(two_minus_xby), .prod(y_next));

endmodule

/*
  fp_inv:
    find multiplicative inverse of an fp

  timing:
    INV_DELAY (INV_NR_STAGES * INV_STAGE_DELAY)
*/
parameter integer INV_NR_STAGES = 2;
parameter integer INV_STAGE_DELAY = 3;
parameter integer INV_DELAY = INV_NR_STAGES * INV_STAGE_DELAY;

module fp_inv (
  input wire clk,
  input wire rst,

  input fp x,
  output fp inv
);
  logic [FP_BITS-2:0] MAGIC_NUMBER = FP_INV_MAGIC_NUM;
  localparam NR_STAGES = INV_NR_STAGES;

  fp [NR_STAGES:0] x_buffer;
  fp [NR_STAGES:0] y_buffer;

  fp abs_x;
  assign abs_x = {1'b0, x.exp, x.mant};

  logic inv_sign;
  pipeline #(.WIDTH(1), .DEPTH(INV_DELAY)) sign_pipe (.clk(clk), .in(x.sign), .out(inv_sign));

  fp init_guess;
  assign init_guess = MAGIC_NUMBER - x[FP_BITS-2:0];

  generate
    genvar i;
    for (i = 0; i < NR_STAGES; i = i + 1) begin
      fp_inv_stage inv_stage (
        .clk(clk),
        .rst(rst),
        .x((i == 0) ? abs_x : x_buffer[i]),
        .y((i == 0) ? init_guess : y_buffer[i]),

        .x_out(x_buffer[i + 1]),
        .y_next(y_buffer[i + 1])
      );
    end
  endgenerate

  // Outputs are last stage in the pipeline
  assign inv = {inv_sign, y_buffer[NR_STAGES].exp, y_buffer[NR_STAGES].mant};

endmodule

`default_nettype none
