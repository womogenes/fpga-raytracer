`default_nettype none

// Compute reflected ray properties after bouncing off of smth

parameter integer RAY_RFLX_FAST_DELAY = VEC3_NORM_DELAY + VEC3_ADD_DELAY + 1;
parameter integer RAY_RFLX_BLEND_DELAY = VEC3_NORM_DELAY + VEC3_LERP_DELAY + VEC3_NORM_DELAY + 2;

module ray_reflector (
  input wire clk,
  input wire rst,

  input fp_vec3 ray_dir,
  input fp_color ray_color,
  input fp_color income_light,

  input fp_vec3 hit_pos,
  input fp_vec3 hit_normal,
  input wire [7:0] hit_mat_idx,
  input wire hit_valid,

  output fp_vec3 new_dir,
  output fp_vec3 new_origin,
  output fp_color new_color,
  output fp_color new_income_light,
  output logic reflect_done,

  // Material dictionary interface
  output logic [7:0] mat_dict_idx,
  input material mat_dict_mat,

  // DEBUG: to be used only for testbench
  input wire [95:0] lfsr_seed
);
  localparam integer MAT_READ_DELAY = 2;
  localparam integer FAST_DATA_DELAY = RAY_RFLX_FAST_DELAY;
  localparam integer BLEND_DATA_DELAY = RAY_RFLX_BLEND_DELAY;
  localparam integer FAST_POST_MAT_DELAY = RAY_RFLX_FAST_DELAY - MAT_READ_DELAY - 1;
  localparam integer BLEND_POST_MAT_DELAY = RAY_RFLX_BLEND_DELAY - MAT_READ_DELAY - 1;
  localparam integer DIFFUSE_DIR_DELAY = VEC3_ADD_DELAY + VEC3_NORM_DELAY;
  localparam integer SPECULAR_DIR_DELAY = VEC3_DOT_DELAY + VEC3_SCALE_DELAY + VEC3_ADD_DELAY;
  localparam integer SPECULAR_DIR_ALIGN_DELAY = DIFFUSE_DIR_DELAY - SPECULAR_DIR_DELAY;
  localparam integer SPEC_AMT_DIR_ALIGN_DELAY = DIFFUSE_DIR_DELAY - MAT_READ_DELAY;
  localparam integer ONE_SUB_SPEC_AMT_DIR_ALIGN_DELAY = DIFFUSE_DIR_DELAY - MAT_READ_DELAY - FP_ADD_DELAY;
  localparam integer BLEND_ORIGIN_INPUT_DELAY = BLEND_DATA_DELAY - VEC3_ADD_DELAY;
  localparam integer BLEND_NORMAL_PIPE_DELAY = BLEND_ORIGIN_INPUT_DELAY - VEC3_SCALE_DELAY;
  localparam integer BLEND_INCOME_PATH_DELAY = MAT_READ_DELAY + VEC3_MUL_DELAY + VEC3_ADD_DELAY;
  localparam integer BLEND_INCOME_ALIGN_DELAY = BLEND_DATA_DELAY - BLEND_INCOME_PATH_DELAY;
  localparam integer TRUE_MAT_ONE_SUB_ALIGN_DELAY = 2 - FP_ADD_DELAY;
  localparam integer BLEND_COLOR_ALIGN_DELAY = BLEND_DATA_DELAY - (7 + VEC3_MUL_DELAY);
  localparam integer FAST_PATH_ALIGN_DELAY = FAST_DATA_DELAY - (VEC3_SCALE_DELAY + VEC3_ADD_DELAY);
  localparam integer FAST_MAT_USE_DELAY = MAT_READ_DELAY + 1;
  localparam integer FAST_COLOR_ALIGN_DELAY = FAST_DATA_DELAY - (FAST_MAT_USE_DELAY + VEC3_MUL_DELAY);
  localparam integer FAST_INCOME_ALIGN_DELAY = FAST_DATA_DELAY - (FAST_MAT_USE_DELAY + VEC3_MUL_DELAY + VEC3_ADD_DELAY);

  logic reflector_busy = 1'b0;

  fp_vec3 ray_dir_active;
  fp_color ray_color_active;
  fp_color income_light_active;
  fp_vec3 hit_pos_active;
  fp_vec3 hit_normal_active;
  logic [7:0] hit_mat_idx_active;

  fp_vec3 ray_dir_latched;
  fp_color ray_color_latched;
  fp_color income_light_latched;
  fp_vec3 hit_pos_latched;
  fp_vec3 hit_normal_latched;
  logic [7:0] hit_mat_idx_latched;

  logic launch_reflect;
  logic mat_ready;
  logic active_fast_path;
  logic active_pure_specular;
  logic reflect_done_fast;
  logic reflect_done_blend;

  assign launch_reflect = hit_valid && !reflector_busy;

  assign ray_dir_active = reflector_busy ? ray_dir_latched : ray_dir;
  assign ray_color_active = reflector_busy ? ray_color_latched : ray_color;
  assign income_light_active = reflector_busy ? income_light_latched : income_light;
  assign hit_pos_active = reflector_busy ? hit_pos_latched : hit_pos;
  assign hit_normal_active = reflector_busy ? hit_normal_latched : hit_normal;
  assign hit_mat_idx_active = reflector_busy ? hit_mat_idx_latched : hit_mat_idx;

  // Delay the launch pulse until the material BRAM output is aligned.
  logic launch_after_mat;
  pipeline #(.WIDTH(1), .DEPTH(MAT_READ_DELAY)) launch_pipe (
    .clk(clk),
    .in(launch_reflect),
    .out(launch_after_mat)
  );
  assign mat_ready = launch_after_mat;

  // ===== BRANCH 0: specular_amt =====
  material hit_mat;

  assign mat_dict_idx = hit_mat_idx_active;
  assign hit_mat = mat_dict_mat;    // 2 cycles behind

  fp spec_amt;
  logic [7:0] rng_specular;
  prng8 rng8 (
    .clk(clk),
    .rst(rst),
    .seed(lfsr_seed[47:0]),
    .rng(rng_specular)
  );
  always_comb begin
    if (rng_specular <= hit_mat.specular_prob) begin
      spec_amt = hit_mat.smoothness;
    end else begin
      spec_amt = FP_ZER0;
    end
  end

  logic pure_diffuse;
  logic pure_specular;
  logic fast_path_now;

  assign pure_diffuse = spec_amt == FP_ZER0;
  assign pure_specular = spec_amt == FP_ONE;
  assign fast_path_now = pure_diffuse || pure_specular;

  logic [7:0] hit_mat_specular_prob;
  assign hit_mat_specular_prob = hit_mat.specular_prob;

  // Calculate (1 - specular_amt)
  fp one_sub_spec_amt;
  fp_add sub_spec_amt (
    .clk(clk),
    .a(FP_ONE),
    .b(spec_amt),
    .is_sub(1'b1),
    .sum(one_sub_spec_amt)
  );

  // Pipeline t, 1-t for direction calculation
  fp spec_amt_piped_dir;
  fp one_sub_spec_amt_piped_dir;
  pipeline #(.WIDTH(FP_BITS), .DEPTH(SPEC_AMT_DIR_ALIGN_DELAY)) spec_amt_pipe (
    .clk(clk),
    .in(spec_amt),
    .out(spec_amt_piped_dir)
  );
  pipeline #(.WIDTH(FP_BITS), .DEPTH(ONE_SUB_SPEC_AMT_DIR_ALIGN_DELAY)) one_sub_spec_amt_pipe (
    .clk(clk),
    .in(one_sub_spec_amt),
    .out(one_sub_spec_amt_piped_dir)
  );

  // ===== BRANCH 1: RAY DIRECTION =====

  // Diffuse direction
  // 18 cycles behind
  fp_vec3 rng_vec;
  prng_sphere_lfsr prng_sphere (
    .clk(clk),
    .rst(rst),
    .seed(lfsr_seed[95:48]),
    .rng_vec(rng_vec)
  );
  fp_vec3 rng_added;
  fp_vec3_add diffuse_adder (
    .clk(clk),
    .rst(rst),
    .v(rng_vec),
    .w(hit_normal_active),
    .is_sub(1'b0),
    .sum(rng_added)
  );
  fp_vec3 diffuse_dir;
  fp_vec3_normalize diffuse_normalizer (
    .clk(clk),
    .rst(rst),
    .v(rng_added),
    .normed(diffuse_dir)
  );

  // Specular direction
  fp_vec3 specular_dir;
  specular_reflect spec_reflector (
    .clk(clk),
    .rst(rst),
    .in_dir(ray_dir_active),
    .normal(hit_normal_active),
    .out_dir(specular_dir)
  );

  fp_vec3 specular_dir_piped;
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(SPECULAR_DIR_ALIGN_DELAY)) spec_dir_pipe (
    .clk(clk),
    .in(specular_dir),
    .out(specular_dir_piped)
  );

  // Lerp from specular dir to diffuse dir
  fp_vec3 new_ray_dir_prenorm;
  fp_vec3 new_dir_blend;
  fp_vec3_lerp lerp_dir (
    .clk(clk),
    .rst(rst),
    .v(diffuse_dir),
    .w(specular_dir_piped),
    .t(spec_amt_piped_dir),
    .one_sub_t(one_sub_spec_amt_piped_dir),
    .lerped(new_ray_dir_prenorm)
  );

  // Normalize blended directions.
  fp_vec3_normalize norm_dir (
    .clk(clk),
    .v(new_ray_dir_prenorm),
    .normed(new_dir_blend)
  );

  fp_vec3 new_dir_fast;
  assign new_dir_fast = active_pure_specular ? specular_dir_piped : diffuse_dir;

  // Pipeline the origin
  fp_vec3 hit_pos_piped;
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(BLEND_ORIGIN_INPUT_DELAY)) origin_pipe (
    .clk(clk),
    .in(hit_pos_active),
    .out(hit_pos_piped)
  );
  fp_vec3 hit_normal_piped;
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(BLEND_NORMAL_PIPE_DELAY)) normal_pipe (
    .clk(clk),
    .in(hit_normal_active),
    .out(hit_normal_piped)
  );
  localparam fp EPSILON = 24'h370000;
  fp_vec3 scaled_normal;
  fp_vec3_scale offset_scale (.clk(clk), .rst(rst), .v(hit_normal_piped), .s(EPSILON), .scaled(scaled_normal));

  fp_vec3 new_origin_blend;
  fp_vec3_add offset_add (
    .clk(clk),
    .rst(rst),
    .v(hit_pos_piped),
    .w(scaled_normal),
    .is_sub(1'b0),
    .sum(new_origin_blend)
  );

  fp_vec3 hit_pos_fast_piped;
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(VEC3_SCALE_DELAY)) hit_pos_fast_pipe (
    .clk(clk),
    .in(hit_pos_active),
    .out(hit_pos_fast_piped)
  );
  fp_vec3 scaled_normal_fast;
  fp_vec3_scale offset_scale_fast (
    .clk(clk),
    .rst(rst),
    .v(hit_normal_active),
    .s(EPSILON),
    .scaled(scaled_normal_fast)
  );
  fp_vec3 new_origin_fast_unaligned;
  fp_vec3_add offset_add_fast (
    .clk(clk),
    .rst(rst),
    .v(hit_pos_fast_piped),
    .w(scaled_normal_fast),
    .is_sub(1'b0),
    .sum(new_origin_fast_unaligned)
  );
  fp_vec3 new_origin_fast;
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(FAST_PATH_ALIGN_DELAY)) new_origin_fast_pipe (
    .clk(clk),
    .in(new_origin_fast_unaligned),
    .out(new_origin_fast)
  );


  // ===== BRANCH 2: NEW COLOR =====

  // Calculate additional incoming light
  // 1 cycle behind
  fp_color extra_income_light;
  fp_vec3_mul mul_extra_income_light (
    .clk(clk),
    .v(ray_color_pipe.pipe[1]),
    .w(hit_mat.emit_color),
    .prod(extra_income_light)
  );

  // Calculate new incoming light
  // 3 cycles behind
  // Requires big pipeline ahead of it to delay accordingly
  fp_color income_light_piped2;
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(2)) income_light_pipe (
    .clk(clk),
    .in(income_light_active),
    .out(income_light_piped2)
  );

  fp_color new_income_light_unpiped;

  fp_vec3_add add_new_income_light (
    .clk(clk),
    .rst(rst),
    .v(extra_income_light),
    .w(income_light_piped2),
    .is_sub(1'b0),
    .sum(new_income_light_unpiped)
  );
  fp_color new_income_light_blend;
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(BLEND_INCOME_ALIGN_DELAY)) new_income_light_pipe (
    .clk(clk),
    .in(new_income_light_unpiped),
    .out(new_income_light_blend)
  );

  fp_color ray_color_fast_piped2;
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(FAST_MAT_USE_DELAY)) ray_color_fast_pipe (
    .clk(clk),
    .in(ray_color_active),
    .out(ray_color_fast_piped2)
  );
  fp_color income_light_fast_piped3;
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(FAST_MAT_USE_DELAY + VEC3_MUL_DELAY)) income_light_fast_pipe (
    .clk(clk),
    .in(income_light_active),
    .out(income_light_fast_piped3)
  );
  fp_color extra_income_light_fast;
  fp_vec3_mul mul_extra_income_light_fast (
    .clk(clk),
    .rst(rst),
    .v(ray_color_fast_piped2),
    .w(hit_mat.emit_color),
    .prod(extra_income_light_fast)
  );
  fp_color new_income_light_fast_unaligned;
  fp_vec3_add add_new_income_light_fast (
    .clk(clk),
    .rst(rst),
    .v(extra_income_light_fast),
    .w(income_light_fast_piped3),
    .is_sub(1'b0),
    .sum(new_income_light_fast_unaligned)
  );
  fp_color new_income_light_fast;
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(FAST_INCOME_ALIGN_DELAY)) new_income_light_fast_pipe (
    .clk(clk),
    .in(new_income_light_fast_unaligned),
    .out(new_income_light_fast)
  );

  // Calculate new ray color
  // Lerp between ray color and specular color
  fp_color true_mat_color;
  fp_color mat_color_piped;
  fp_color mat_spec_color_piped;
  fp one_sub_spec_amt_piped_color;

  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(2)) mat_color_pipe (
    .clk(clk),
    .in(hit_mat.color),
    .out(mat_color_piped)
  );
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(2)) mat_spec_color_pipe (
    .clk(clk),
    .in(hit_mat.spec_color),
    .out(mat_spec_color_piped)
  );
  pipeline #(.WIDTH(FP_BITS), .DEPTH(TRUE_MAT_ONE_SUB_ALIGN_DELAY)) one_sub_spec_amt_color_pipe (
    .clk(clk),
    .in(one_sub_spec_amt),
    .out(one_sub_spec_amt_piped_color)
  );

  fp_vec3_lerp lerp_true_mat_color (
    .clk(clk),
    .rst(rst),
    .v(mat_color_piped),
    .w(mat_spec_color_piped),
    .t(spec_amt_pipe.pipe[1]),
    .one_sub_t(one_sub_spec_amt_piped_color),
    .lerped(true_mat_color)
  );

  // Combine ray_color and true_mat_color to get new ray color
  fp_color ray_color_piped7;
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(7)) ray_color_pipe (
    .clk(clk),
    .in(ray_color_active),
    .out(ray_color_piped7)
  );
  fp_color new_color_unpiped;
  fp_vec3_mul mul_new_ray_color (
    .clk(clk),
    .rst(rst),
    .v(ray_color_piped7),
    .w(true_mat_color),
    .prod(new_color_unpiped)
  );
  fp_color new_color_blend;
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(BLEND_COLOR_ALIGN_DELAY)) new_ray_color_pipe (
    .clk(clk),
    .in(new_color_unpiped),
    .out(new_color_blend)
  );

  fp_color new_color_diffuse_unaligned;
  fp_color new_color_specular_unaligned;
  fp_vec3_mul mul_new_ray_color_diffuse (
    .clk(clk),
    .rst(rst),
    .v(ray_color_fast_piped2),
    .w(hit_mat.color),
    .prod(new_color_diffuse_unaligned)
  );
  fp_vec3_mul mul_new_ray_color_specular (
    .clk(clk),
    .rst(rst),
    .v(ray_color_fast_piped2),
    .w(hit_mat.spec_color),
    .prod(new_color_specular_unaligned)
  );
  fp_color new_color_fast_unaligned;
  assign new_color_fast_unaligned = active_pure_specular ? new_color_specular_unaligned : new_color_diffuse_unaligned;
  fp_color new_color_fast;
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(FAST_COLOR_ALIGN_DELAY)) new_color_fast_pipe (
    .clk(clk),
    .in(new_color_fast_unaligned),
    .out(new_color_fast)
  );

  assign new_dir = active_fast_path ? new_dir_fast : new_dir_blend;
  assign new_origin = active_fast_path ? new_origin_fast : new_origin_blend;
  assign new_color = active_fast_path ? new_color_fast : new_color_blend;
  assign new_income_light = active_fast_path ? new_income_light_fast : new_income_light_blend;
  assign reflect_done = reflect_done_fast || reflect_done_blend;

  pipeline #(.WIDTH(1), .DEPTH(FAST_POST_MAT_DELAY)) fast_done_pipe (
    .clk(clk),
    .in(mat_ready && fast_path_now),
    .out(reflect_done_fast)
  );
  pipeline #(.WIDTH(1), .DEPTH(BLEND_POST_MAT_DELAY)) blend_done_pipe (
    .clk(clk),
    .in(mat_ready && !fast_path_now),
    .out(reflect_done_blend)
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      reflector_busy <= 1'b0;
      active_fast_path <= 1'b0;
      active_pure_specular <= 1'b0;
    end else begin
      if (launch_reflect) begin
        reflector_busy <= 1'b1;
        ray_dir_latched <= ray_dir;
        ray_color_latched <= ray_color;
        income_light_latched <= income_light;
        hit_pos_latched <= hit_pos;
        hit_normal_latched <= hit_normal;
        hit_mat_idx_latched <= hit_mat_idx;
      end

      if (mat_ready) begin
        active_fast_path <= fast_path_now;
        active_pure_specular <= pure_specular;
      end

      if (reflect_done_fast || reflect_done_blend) begin
        reflector_busy <= 1'b0;
      end
    end
  end

  // TODO temp pipeline for debug
  // fp_vec3 hit_pos_superpiped;
  // pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(36)) new_income_light_pipe (
  //   .clk(clk),
  //   .in(hit_pos),
  //   .out(hit_pos_superpiped)
  // );

  // assign new_income_light = new_dir;
  // fp_vec3_scale pos_scale (.clk(clk), .rst(rst), .v(hit_pos_superpiped), .s(24'h3c5555), .scaled(new_income_light));
  // assign new_income_light = new_color;

    
endmodule

`default_nettype wire
