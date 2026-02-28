`default_nettype none

module specular_reflect (
  input wire clk,
  input wire rst,

  input fp_vec3 in_dir,
  input fp_vec3 normal,

  output fp_vec3 out_dir
);
  fp dot_in_norm;
  fp dot_in_norm_x2;
  fp_vec3 normal_piped;
  fp_vec3 in_dir_piped;
  fp_vec3 normal_scaled;

  // Calculate dot product times 2
  // VEC3_DOT_DELAY (3) cycles behind
  fp_vec3_dot dot1(
    .clk(clk),
    .v(in_dir),
    .w(normal),
    .dot(dot_in_norm)
  );
  fp_shift #(.SHIFT_AMT(1)) shift1 (
    .a(dot_in_norm),
    .shifted(dot_in_norm_x2)
  );
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(VEC3_DOT_DELAY)) normal_pipe (
    .clk(clk),
    .in(normal),
    .out(normal_piped)
  );

  // Multiply dot by normal vector
  // VEC3_DOT_DELAY + VEC3_SCALE_DELAY (4) cycles behind
  fp_vec3_scale scale_norm (
    .clk(clk),
    .v(normal_piped),
    .s(dot_in_norm_x2),
    .scaled(normal_scaled)
  );
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(VEC3_DOT_DELAY + VEC3_SCALE_DELAY)) in_dir_pipe (
    .clk(clk),
    .in(in_dir),
    .out(in_dir_piped)
  );

  // Calculate difference
  // VEC3_DOT_DELAY + VEC3_SCALE_DELAY + VEC3_ADD_DELAY (5) cycles behind
  fp_vec3_add add_out_dir (
    .clk(clk),
    .v(in_dir_piped),
    .w(normal_scaled),
    .is_sub(1'b1),
    .sum(out_dir)
  );

endmodule

`default_nettype wire
