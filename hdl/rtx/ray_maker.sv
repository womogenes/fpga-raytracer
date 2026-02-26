`default_nettype none

// Make ray in 3D given camera config and pixel coordinates.

module ray_maker #(
  parameter WIDTH = 1280,
  parameter HEIGHT = 720,
  parameter FOCAL_LENGTH = 10,
  parameter DOF = 0
) (
  input wire clk,
  input wire rst,
  
  input camera cam,
  input wire [10:0] pixel_h_in,
  input wire [9:0] pixel_v_in,
  input wire new_ray,

  output fp_vec3 ray_origin,
  output fp_vec3 ray_dir,
  output logic ray_valid,

  output logic [10:0] pixel_h_out,
  output logic [9:0] pixel_v_out,

  // DEBUG: to be used only for testbench
  input wire [95:0] lfsr_seed
);
  localparam integer RAY_MAKER_DELAY = 1 + 1 + FP_ADD_DELAY + VEC3_SCALE_DELAY + VEC3_ADD_DELAY + VEC3_NORM_DELAY;

  // Normalize by centering at zero
  logic signed [10:0] pixel_h_norm;
  logic signed [9:0] pixel_v_norm;

  assign pixel_h_norm = $signed(pixel_h_in) - $signed(WIDTH / 2);
  assign pixel_v_norm = $signed(HEIGHT / 2) - $signed(pixel_v_in);

  // Normalized device coordinates
  fp u, v;
  make_fp #(.WIDTH(11)) u_maker (.clk(clk), .n(pixel_h_norm), .x(u));
  make_fp #(.WIDTH(10)) v_maker (.clk(clk), .n(pixel_v_norm), .x(v));

  // Add some noise to u and v
  logic [7:0] noise_u_int8, noise_v_int8;
  prng8 rng8_u (.clk(clk), .rst(rst), .seed(lfsr_seed[7:0]), .rng(noise_u_int8));
  prng8 rng8_v (.clk(clk), .rst(rst), .seed(lfsr_seed[15:8]), .rng(noise_v_int8));

  // TODO: make this more precise for DOF
  fp noise_u, noise_v;
  make_fp #(.WIDTH(8), .FRAC(-8)) noise_u_maker (.clk(clk), .n(noise_u_int8), .x(noise_u));
  make_fp #(.WIDTH(8), .FRAC(-8)) noise_v_maker (.clk(clk), .n(noise_v_int8), .x(noise_v));

  fp u_noisy, v_noisy;
  fp_add add_u_noisy (.clk(clk), .a(u), .b(noise_u), .is_sub(1'b0), .sum(u_noisy));
  fp_add add_v_noisy (.clk(clk), .a(v), .b(noise_v), .is_sub(1'b0), .sum(v_noisy));

  // Multiply by right and up vectors
  fp_vec3 right_scaled, up_scaled;
  fp_vec3_scale scale_right(.clk(clk), .rst(rst), .v(cam.right), .s(u_noisy), .scaled(right_scaled));
  fp_vec3_scale scale_up(.clk(clk), .rst(rst), .v(cam.up), .s(v_noisy), .scaled(up_scaled));

  // Add everything together
  // result 5 cycles behind
  fp_vec3 sum_ru;
  fp_vec3_add add_ru(.clk(clk), .rst(rst), .v(right_scaled), .w(up_scaled), .is_sub(1'b0), .sum(sum_ru));

  fp_vec3 ray_unnormed;
  fp_vec3_add add_ray_unnormed(.clk(clk), .rst(rst), .v(sum_ru), .w(cam.forward), .is_sub(1'b0), .sum(ray_unnormed));

  // Normalize it
  fp_vec3_normalize norm_ray_dir(.clk(clk), .v(ray_unnormed), .normed(ray_dir));

  // Ray origin == camera origin for now
  assign ray_origin = cam.origin;

  pipeline #(.WIDTH(11), .DEPTH(RAY_MAKER_DELAY)) pixel_h_pipe (.clk(clk), .in(pixel_h_in), .out(pixel_h_out));
  pipeline #(.WIDTH(10), .DEPTH(RAY_MAKER_DELAY)) pixel_v_pipe (.clk(clk), .in(pixel_v_in), .out(pixel_v_out));

  // Pipeline the valid signal
  pipeline #(
    .WIDTH(1),
    .DEPTH(RAY_MAKER_DELAY)
  ) valid_pipe (.clk(clk), .in(new_ray), .out(ray_valid));
endmodule

`default_nettype wire
