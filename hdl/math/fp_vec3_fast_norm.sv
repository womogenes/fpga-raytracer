`default_nettype none

parameter integer FAST_INV_SQRT_DELAY = 2;
parameter integer FAST_VEC3_NORM_DELAY = VEC3_DOT_DELAY + FAST_INV_SQRT_DELAY + 1;

module fp_inv_sqrt_fast (
  input wire clk,
  input wire rst,

  input fp x,
  input wire x_valid,

  output fp inv_sqrt,
  output wire inv_sqrt_valid
);
  fp init_guess;

  assign init_guess = FP_INV_SQRT_MAGIC_NUM - (x >> 1);

  pipeline #(.WIDTH(FP_BITS), .DEPTH(FAST_INV_SQRT_DELAY)) guess_pipe (
    .clk(clk),
    .in(init_guess),
    .out(inv_sqrt)
  );
  pipeline #(.WIDTH(1), .DEPTH(FAST_INV_SQRT_DELAY)) valid_pipe (
    .clk(clk),
    .in(x_valid),
    .out(inv_sqrt_valid)
  );
endmodule

module fp_vec3_normalize_fast (
  input wire clk,
  input wire rst,
  input fp_vec3 v,
  output fp_vec3 normed
);
  fp mag_sq;
  fp mag_inv;
  fp_vec3 v_piped;

  fp_vec3_dot dot_mag_sq (
    .clk(clk),
    .rst(rst),
    .v(v),
    .w(v),
    .dot(mag_sq)
  );

  fp_inv_sqrt_fast inv_sqrt_mag (
    .clk(clk),
    .rst(rst),
    .x(mag_sq),
    .x_valid(1'b1),
    .inv_sqrt(mag_inv),
    .inv_sqrt_valid()
  );

  pipeline #(
    .WIDTH(FP_VEC3_BITS),
    .DEPTH(VEC3_DOT_DELAY + FAST_INV_SQRT_DELAY)
  ) v_pipe (
    .clk(clk),
    .in(v),
    .out(v_piped)
  );

  fp_vec3_scale scale_a_norm (
    .clk(clk),
    .rst(rst),
    .v(v_piped),
    .s(mag_inv),
    .scaled(normed)
  );
endmodule

`default_nettype wire
