`default_nettype none

// Compute intersection between ray and sphere

parameter integer SPHERE_INTX_QR_STAGE_DELAY = 1 + VEC3_DOT_DELAY + 1 + QR_SOLVER_DELAY;
parameter integer SPHERE_INTX_DELAY = SPHERE_INTX_QR_STAGE_DELAY + 4;

module sphere_intersector (
  input wire clk,
  input wire rst,

  input fp_vec3 ray_origin,
  input fp_vec3 ray_dir,
  input fp_vec3 sphere_center,
  input fp sphere_rad_sq,
  input fp sphere_rad_inv,

  output logic hit,
  output fp_vec3 hit_pos,
  output fp hit_dist,
  output fp_vec3 hit_norm
);
  fp_vec3 L;                // ray_origin - sphere_center
  fp ray_dir_dot_L;         // ray_dir * L
  fp L_mag_sq;              // |L|^2
  fp_vec3 L_piped;
  fp b;
  fp b_piped;               // delay 1 signal for c calculation
  fp c;                     // quadratic coefficients
  fp x0;                    // solution to QR solver
  fp_vec3 ray_dir_by_x0;    // vector from origin to hit point
  fp_vec3 hit_pos_prepiped; // unpiped version of hit position
  fp_vec3 hit_norm_prenorm; // normal vector to hit pos before normalization

  // huge pipelines for everything
  fp_vec3 ray_dir_piped;
  fp_vec3 ray_origin_piped;
  fp sphere_rad_sq_piped;
  fp sphere_rad_inv_piped;

  // how many cycles till we finish QR solver?
  localparam integer QR_STAGE_DELAY = SPHERE_INTX_QR_STAGE_DELAY;

  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(QR_STAGE_DELAY)) ray_dir_pipe (
    .clk(clk),
    .in(ray_dir),
    .out(ray_dir_piped)
  );
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(QR_STAGE_DELAY + 1)) ray_origin_pipe (
    .clk(clk),
    .in(ray_origin),
    .out(ray_origin_piped)
  );

  // result 1 cycle behind
  fp_vec3_add add_L(.clk(clk), .v(ray_origin), .w(sphere_center), .is_sub(1'b1), .sum(L));

  // result 4 cycles behind
  fp_vec3_dot dot_ray_dir_dot_L(.clk(clk), .v(ray_dir_pipe.pipe[0]), .w(L), .dot(ray_dir_dot_L));
  fp_vec3_dot dot_L_mag_sq(.clk(clk), .v(L), .w(L), .dot(L_mag_sq));
  pipeline #(.WIDTH(FP_BITS), .DEPTH(1 + VEC3_DOT_DELAY)) sphere_rad_pipe (
    .clk(clk),
    .in(sphere_rad_sq),
    .out(sphere_rad_sq_piped)
  );

  // result 5 cycles behind (right before QR solver)
  fp_shift #(.SHIFT_AMT(1)) shift_b (.a(ray_dir_dot_L), .shifted(b));
  pipeline #(.WIDTH(FP_BITS), .DEPTH(1)) b_pipe (.clk(clk), .in(b), .out(b_piped));
  fp_add add_c(.clk(clk), .a(L_mag_sq), .b(sphere_rad_sq_piped), .is_sub(1'b1), .sum(c));

  // result 17 cycles behind (after QR solver)
  quadratic_solver qr_solver(.clk(clk), .b(b_piped), .c(c), .x0(x0));

  // result 18 cycles behind
  fp_vec3_scale scale_ray_dir(.clk(clk), .v(ray_dir_piped), .s(x0), .scaled(ray_dir_by_x0));
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(VEC3_DOT_DELAY + 1 + QR_SOLVER_DELAY + 1)) L_pipe (
    .clk(clk),
    .in(L),
    .out(L_piped)
  );

  // result 19 cycles behind
  fp_vec3_add add_hit_pos(.clk(clk), .v(ray_dir_by_x0), .w(ray_origin_piped), .is_sub(1'b0), .sum(hit_pos_prepiped));
  fp_vec3_add add_hit_norm_prenorm(.clk(clk), .v(ray_dir_by_x0), .w(L_piped), .is_sub(1'b0), .sum(hit_norm_prenorm));
  pipeline #(.WIDTH(FP_BITS), .DEPTH(QR_STAGE_DELAY + 2)) sphere_rad_inv_pipe (
    .clk(clk),
    .in(sphere_rad_inv),
    .out(sphere_rad_inv_piped)
  );

  // result 20 cycles behind
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(1)) hit_pos_pipe (.clk(clk), .in(hit_pos_prepiped), .out(hit_pos));
  fp_vec3_scale scale_hit_norm(.clk(clk), .v(hit_norm_prenorm), .s(sphere_rad_inv_piped), .scaled(hit_norm));
  pipeline #(.WIDTH(1), .DEPTH(3)) hit_pipe (.clk(clk), .in(qr_solver.valid && ~x0.sign), .out(hit));
  pipeline #(.WIDTH(FP_BITS), .DEPTH(3)) hit_dist_pipe (.clk(clk), .in(x0), .out(hit_dist));

endmodule

`default_nettype wire
