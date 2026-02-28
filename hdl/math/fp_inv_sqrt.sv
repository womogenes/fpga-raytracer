// Compute inverse square root
`default_nettype none

/*
  Optimizations:
    - Ignore the `valid` pipe and just trust that this module is fully pipelined
      with 8-cycle delay
*/

/*
  inv_sqrt_stage:
    computes one stage of Newton's method for inverse square roots

  inputs:
    x: the number to be inverse-square-rooted
    y: current guess

  timing:
    4 clock cycles
*/
module fp_inv_sqrt_stage (
  input wire clk,
  input wire rst,

  input fp x,
  input fp y,
  input wire valid_in,

  output fp x_out,
  output fp y_next,
  output wire valid_out
);
  // TODO: adjust magic constants
  localparam fp three = FP_THREE;

  fp y_piped4;

  pipeline #(.WIDTH(FP_BITS), .DEPTH(4)) x_pipe (.clk(clk), .in(x), .out(x_out));
  pipeline #(.WIDTH(FP_BITS), .DEPTH(3)) y_pipe (.clk(clk), .in(y), .out(y_piped4));
  pipeline #(.WIDTH(1), .DEPTH(4)) valid_pipe (.clk(clk), .in(valid_in), .out(valid_out));

  fp y_sq;              // y * y
  fp y_sq_by_x;         // x * y * y
  fp sub;               // (3 - x * y * y)
  fp frac;              // (3 - x * y * y) / 2
  
  fp_mul mul_y_sq(.clk(clk), .rst(rst), .a(y), .b(y), .prod(y_sq));
  fp_mul mul_y_sq_by_x(.clk(clk), .rst(rst), .a(y_sq), .b(x_pipe.pipe[0]), .prod(y_sq_by_x));
  
  fp_add add_sub(.clk(clk), .rst(rst), .a(three), .b(y_sq_by_x), .is_sub(1'b1), .sum(sub));
  fp_shift #(.SHIFT_AMT(-1)) div2_frac (.a(sub), .shifted(frac));
  
  // Final answer
  fp_mul mul_y_next(.clk(clk), .rst(rst), .a(frac), .b(y_piped4), .prod(y_next));
endmodule

/*
  inv_sqrt:
    does the whole inverse square root shebang using Newton-Rhapson

  inputs:
    x: the number to be inverse-square-rooted
    x_valid: whether the input is valid

  timing:
    (INV_SQRT_NR_STAGES * INV_SQRT_STAGE_DELAY) cycle delay
*/

module fp_inv_sqrt (
  input wire clk,
  input wire rst,

  input fp x,
  input wire x_valid,

  output fp inv_sqrt,
  output wire inv_sqrt_valid
);
  // localparam fp half = {1'b0, 7'b011_1110, 16'b0};
  localparam fp MAGIC_NUMBER = FP_INV_SQRT_MAGIC_NUM;
  localparam integer NR_STAGES = INV_SQRT_NR_STAGES;

  // fp half_x;
  // fp_mul half_x_mult(.a(half), .b(x), .prod(half_x));

  fp [NR_STAGES:0] x_buffer;
  fp [NR_STAGES:0] y_buffer;
  logic [NR_STAGES:0] valid_buffer;

  // First stage assume combinational
  fp init_guess;
  assign init_guess = MAGIC_NUMBER - (x >> 1); // what the fuck???
  
  generate
    genvar i;
    for (i = 0; i < NR_STAGES; i = i + 1) begin
      fp_inv_sqrt_stage inv_sqrt_stage (
        .clk(clk),
        .rst(rst),
        .x((i == 0) ? x : x_buffer[i]),
        .y((i == 0) ? init_guess : y_buffer[i]),
        .valid_in((i == 0) ? x_valid : valid_buffer[i]),

        .x_out(x_buffer[i + 1]),
        .y_next(y_buffer[i + 1]),
        .valid_out(valid_buffer[i + 1])
      );
    end
  endgenerate

  // Outputs are last stage in the pipeline
  assign inv_sqrt = y_buffer[NR_STAGES];
  assign inv_sqrt_valid = valid_buffer[NR_STAGES];
endmodule

`default_nettype wire
