/*
  Add a vec3 to a vec3

  Timing: 1 cycle
*/

`default_nettype none

module fp_vec3_add (
  input wire clk,
  input wire rst,
  input fp_vec3 v,
  input fp_vec3 w,
  input wire is_sub,

  output fp_vec3 sum
);
  fp_add add_x(.clk(clk), .rst(rst), .a(v.x), .b(w.x), .is_sub(is_sub), .sum(sum.x));
  fp_add add_y(.clk(clk), .rst(rst), .a(v.y), .b(w.y), .is_sub(is_sub), .sum(sum.y));
  fp_add add_z(.clk(clk), .rst(rst), .a(v.z), .b(w.z), .is_sub(is_sub), .sum(sum.z));
endmodule

/*
  Multiply a vec3 by a vec3

  Timing: 1 cycle
*/
module fp_vec3_mul (
  input wire clk,
  input wire rst,
  input fp_vec3 v,
  input fp_vec3 w,

  output fp_vec3 prod
);
  fp_mul mul_x(.clk(clk), .rst(rst), .a(v.x), .b(w.x), .prod(prod.x));
  fp_mul mul_y(.clk(clk), .rst(rst), .a(v.y), .b(w.y), .prod(prod.y));
  fp_mul mul_z(.clk(clk), .rst(rst), .a(v.z), .b(w.z), .prod(prod.z));
endmodule

/*
  Multiply a vec3 by a scalar

  Timing: 1 cycle
*/
module fp_vec3_scale (
  input wire clk,
  input wire rst,
  input fp_vec3 v,
  input fp s,

  output fp_vec3 scaled
);
  fp_mul mul_x(.clk(clk), .rst(rst), .a(v.x), .b(s), .prod(scaled.x));
  fp_mul mul_y(.clk(clk), .rst(rst), .a(v.y), .b(s), .prod(scaled.y));
  fp_mul mul_z(.clk(clk), .rst(rst), .a(v.z), .b(s), .prod(scaled.z));
endmodule

/*
  Shift each component of a vec3 by some integer amount
  Purely combinational
*/
module fp_vec3_shift #(
  parameter integer SHIFT_AMT
) (
  input fp_vec3 v,
  output fp_vec3 shifted
);
  fp_shift #(.SHIFT_AMT(SHIFT_AMT)) shift_x (.a(v.x), .shifted(shifted.x));
  fp_shift #(.SHIFT_AMT(SHIFT_AMT)) shift_y (.a(v.y), .shifted(shifted.y));
  fp_shift #(.SHIFT_AMT(SHIFT_AMT)) shift_z (.a(v.z), .shifted(shifted.z));
endmodule

/*
  Dot product of two vec3s

  Timing:
    VEC3_DOT_DELAY cycles
    Currently 3 (mul - 1, add - 1, add - 1)
*/
module fp_vec3_dot (
  input wire clk,
  input wire rst,
  input fp_vec3 v,
  input fp_vec3 w,
  output fp dot
);
  fp_vec3 prod;
  fp sum_xy, z_piped2;

  fp_vec3_mul mul(.clk(clk), .v(v), .w(w), .prod(prod));

  // Add the elementwise products
  fp_add add_xy(.clk(clk), .a(prod.x), .b(prod.y), .is_sub(1'b0), .sum(sum_xy));

  // Store z-value because pipeline timing
  pipeline #(.WIDTH(FP_BITS), .DEPTH(1)) z_pipe (.clk(clk), .in(prod.z), .out(z_piped2));

  // Final add
  fp_add add_xyz(.clk(clk), .a(sum_xy), .b(z_piped2), .is_sub(1'b0), .sum(dot));
endmodule

/*
  Cross product of two vec3s

  Timing:
    VEC3_CROSS_DELAY cycles
    Currently 2 (mul - 1, add - 1)
*/
module fp_vec3_cross (
  input wire clk,
  input wire rst,
  input fp_vec3 v,
  input fp_vec3 w,
  output fp_vec3 cross_prod
);
  fp xy, yx, xz, zx, yz, zy;

  fp_mul xy_mul ( .clk(clk), .rst(rst), .a(v.x), .b(w.y), .prod(xy) );
  fp_mul yx_mul ( .clk(clk), .rst(rst), .a(v.y), .b(w.x), .prod(yx) );
  fp_mul xz_mul ( .clk(clk), .rst(rst), .a(v.x), .b(w.z), .prod(xz) );
  fp_mul zx_mul ( .clk(clk), .rst(rst), .a(v.z), .b(w.x), .prod(zx) );
  fp_mul yz_mul ( .clk(clk), .rst(rst), .a(v.y), .b(w.z), .prod(yz) );
  fp_mul zy_mul ( .clk(clk), .rst(rst), .a(v.z), .b(w.y), .prod(zy) );

  fp_add x_add  ( .clk(clk), .rst(rst), .a(yz),  .b(zy),  .is_sub(1'b1), .sum(cross_prod.x));
  fp_add y_add  ( .clk(clk), .rst(rst), .a(zx),  .b(xz),  .is_sub(1'b1), .sum(cross_prod.y));
  fp_add z_add  ( .clk(clk), .rst(rst), .a(xy),  .b(yx),  .is_sub(1'b1), .sum(cross_prod.z));
  
endmodule

/*
  Normalize a vector to have magnitude 1 using inv_sqrt

  Timing:
    VEC3_DOT_DELAY + INV_SQRT_DELAY + SCALE_DELAY (1)
*/
module fp_vec3_normalize (
  input wire clk,
  input wire rst,
  input fp_vec3 v,
  output fp_vec3 normed
);
  // Find |v * v|, i.e. x^2 + y^2 + z^2
  // VEC3_DOT_DELAY cycles
  fp mag_sq;
  fp_vec3_dot dot_mag_sq(.clk(clk), .v(v), .w(v), .dot(mag_sq));

  // Find 1/mag(a)
  // INV_SQRT_DELAY cycles
  fp mag_inv;
  fp_inv_sqrt inv_sqrt_mag(
    .clk(clk), .rst(rst),
    .x(mag_sq), .x_valid(1'b1),
    .inv_sqrt(mag_inv), .inv_sqrt_valid()
  );

  // Delay a for the scaling portion
  fp_vec3 v_piped;
  pipeline #(
    .WIDTH(FP_VEC3_BITS),
    .DEPTH(VEC3_DOT_DELAY + INV_SQRT_DELAY)
  ) v_pipe (
    .clk(clk), .in(v), .out(v_piped)
  );

  // Scaling portion
  // 1 cycle
  fp_vec3_scale scale_a_norm(.clk(clk), .v(v_piped), .s(mag_inv), .scaled(normed));
endmodule

/*
  Lerp between two fp_vec3s. Requires both t and one_sub_t for efficiency.

  Timing:
    2 cycles: scale (1) + add (1)
*/
module fp_vec3_lerp (
  input wire clk,
  input wire rst,

  input fp_vec3 v,
  input fp_vec3 w,
  input fp t,
  input fp one_sub_t,

  output fp_vec3 lerped
);
  fp_vec3 v_scaled, w_scaled;

  // Calculate v * (1-t) and w * t
  fp_vec3_scale v_scaler(.clk(clk), .rst(rst), .v(v), .s(one_sub_t), .scaled(v_scaled));
  fp_vec3_scale w_scaler(.clk(clk), .rst(rst), .v(w), .s(t), .scaled(w_scaled));

  // Add them together
  fp_vec3_add adder(.clk(clk), .rst(rst), .v(v_scaled), .w(w_scaled), .is_sub(0), .sum(lerped));
endmodule

`default_nettype wire
