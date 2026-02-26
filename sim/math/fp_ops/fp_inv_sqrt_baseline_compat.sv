`default_nettype none

module fp_inv_sqrt_stage_baseline (
  input wire clk,
  input wire rst,
  input fp x,
  input fp y,
  input wire valid_in,
  output fp x_out,
  output fp y_next,
  output wire valid_out
);
  localparam fp three = FP_THREE;

  fp y_piped5;
  fp y_sq;
  fp y_sq_by_x;
  fp sub;
  fp frac;

  pipeline #(.WIDTH(FP_BITS), .DEPTH(5)) x_pipe (.clk(clk), .in(x), .out(x_out));
  pipeline #(.WIDTH(FP_BITS), .DEPTH(4)) y_pipe (.clk(clk), .in(y), .out(y_piped5));
  pipeline #(.WIDTH(1), .DEPTH(5)) valid_pipe (.clk(clk), .in(valid_in), .out(valid_out));

  fp_mul mul_y_sq(.clk(clk), .a(y), .b(y), .prod(y_sq));
  fp_mul mul_y_sq_by_x(.clk(clk), .a(y_sq), .b(x_pipe.pipe[0]), .prod(y_sq_by_x));
  fp_add_baseline add_sub(.clk(clk), .a(three), .b(y_sq_by_x), .is_sub(1'b1), .sum(sub));
  fp_shift #(.SHIFT_AMT(-1)) div2_frac(.a(sub), .shifted(frac));
  fp_mul mul_y_next(.clk(clk), .a(frac), .b(y_piped5), .prod(y_next));
endmodule

module fp_inv_sqrt_baseline (
  input wire clk,
  input wire rst,
  input fp x,
  input wire x_valid,
  output fp inv_sqrt,
  output wire inv_sqrt_valid
);
  localparam fp MAGIC_NUMBER = FP_INV_SQRT_MAGIC_NUM;
  localparam integer NR_STAGES = INV_SQRT_NR_STAGES;

  fp [NR_STAGES:0] x_buffer;
  fp [NR_STAGES:0] y_buffer;
  logic [NR_STAGES:0] valid_buffer;

  fp init_guess;
  assign init_guess = MAGIC_NUMBER - (x >> 1);

  generate
    genvar i;
    for (i = 0; i < NR_STAGES; i = i + 1) begin : gen_inv_sqrt_stage
      fp_inv_sqrt_stage_baseline inv_sqrt_stage (
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

  assign inv_sqrt = y_buffer[NR_STAGES];
  assign inv_sqrt_valid = valid_buffer[NR_STAGES];
endmodule

`default_nettype wire
