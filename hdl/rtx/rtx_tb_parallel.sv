`default_nettype none

// Testbench for rtx
// All this does is wrap rtx but provide scene buffer as well

module rtx_tb_parallel #(
  parameter WIDTH = 1280,
  parameter HEIGHT = 720
) (
  input wire clk,
  input wire rst,
  input camera cam,
  input wire [$clog2(MAX_NUM_OBJS)-1:0] num_objs,
  input wire [7:0] max_bounces,

  input wire [10:0] pixel_h_in,
  input wire [9:0] pixel_v_in,
  input wire new_ray,

  output logic [15:0] rtx_pixel,
  output logic ray_done,

  // DEBUG: to be used only for testbench
  input wire [95:0] lfsr_seed
);
  object obj;
  logic [7:0] mat_dict_idx;
  material mat_dict_mat;

  logic [10:0] pixel_h_caster;
  logic [9:0] pixel_v_caster;

  fp_vec3 ray_origin, ray_dir;
  logic ray_valid_caster;

  // Initialize scene buffer
  // Bind inputs to ray tracer
  scene_buffer #(.INIT_FILE("data/scene_buffer.mem")) scene_buf (
    .clk(clk),
    .rst(rst),
    .num_objs(num_objs),
    .obj(obj)
  );

  material_dictionary #(.INIT_FILE("data/mat_dict.mem")) mat_dict (
    .clk(clk),
    .rst(rst),
    .mat_idx(mat_dict_idx),
    .mat(mat_dict_mat)
  );

  ray_maker #(
    .WIDTH(WIDTH),
    .HEIGHT(HEIGHT)
  ) maker (
    .clk(clk),
    .rst(rst),

    // Inputs
    .cam(cam),
    .pixel_h_in(pixel_h_in),
    .pixel_v_in(pixel_v_in),
    .ray_origin(ray_origin),
    .ray_dir(ray_dir),
    .ray_valid(ray_valid_caster),
    .new_ray(new_ray),

    // Outputs
    .pixel_h_out(pixel_h_caster),
    .pixel_v_out(pixel_v_caster),

    .lfsr_seed(lfsr_seed)
  );

  logic ray_done_tracer;
  fp_color pixel_color;

  ray_tracer #(
    .WIDTH(WIDTH),
    .HEIGHT(HEIGHT)
  ) tracer (
    .clk(clk),
    .rst(rst),

    // Input
    .pixel_h_in(pixel_h_caster),
    .pixel_v_in(pixel_v_caster),
    .ray_origin(ray_origin),
    .ray_dir(ray_dir),
    .ray_valid(ray_valid_caster),
    
    .lfsr_seed(lfsr_seed),

    // Doubles as a "pixel valid" signal
    .ray_done(ray_done_tracer),
    .pixel_color(pixel_color),
    // .pixel_h_out(pixel_h),
    // .pixel_v_out(pixel_v),

    .max_bounces(max_bounces),

    // Scene buffer interface
    .num_objs(num_objs),
    .obj(obj),

    // Material dictionary interface
    .mat_dict_idx(mat_dict_idx),
    .mat_dict_mat(mat_dict_mat)
  );

  // Convert to 565 representation
  // fp_color pixel_color_clipped;
  // fp_clip_upper #(.UPPER_BOUND(FP_ONE)) r_min(.clk(clk), .a(pixel_color.r), .clipped(pixel_color_clipped.r));
  // fp_clip_upper #(.UPPER_BOUND(FP_ONE)) g_min(.clk(clk), .a(pixel_color.g), .clipped(pixel_color_clipped.g));
  // fp_clip_upper #(.UPPER_BOUND(FP_ONE)) b_min(.clk(clk), .a(pixel_color.b), .clipped(pixel_color_clipped.b));

  convert_fp_uint #(.WIDTH(5), .FRAC(5)) r_convert (.clk(clk), .x(pixel_color.r), .n(rtx_pixel[4:0]));
  convert_fp_uint #(.WIDTH(6), .FRAC(6)) g_convert (.clk(clk), .x(pixel_color.g), .n(rtx_pixel[10:5]));
  convert_fp_uint #(.WIDTH(5), .FRAC(5)) b_convert (.clk(clk), .x(pixel_color.b), .n(rtx_pixel[15:11]));

  // Delay ray_done by 1 cycle for the conversion
  pipeline #(.WIDTH(1), .DEPTH(1)) ray_done_pipe (.clk(clk), .in(ray_done_tracer), .out(ray_done));

endmodule

`default_nettype wire
