`default_nettype none

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
  localparam integer REFLECT_DONE_DELAY = 37;
  localparam integer NEW_DIR_DELAY = 29;

  pipeline #(.WIDTH(1), .DEPTH(REFLECT_DONE_DELAY)) done_pipe (
    .clk(clk),
    .in(hit_valid),
    .out(reflect_done)
  );

  material hit_mat;

  assign mat_dict_idx = hit_mat_idx;
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

  fp one_sub_spec_amt;
  fp_add sub_spec_amt (
    .clk(clk),
    .a(FP_ONE),
    .b(spec_amt),
    .is_sub(1'b1),
    .sum(one_sub_spec_amt)
  );

  fp spec_amt_piped_dir;
  fp one_sub_spec_amt_piped_dir;
  pipeline #(.WIDTH(FP_BITS), .DEPTH(13)) spec_amt_pipe (
    .clk(clk),
    .in(spec_amt),
    .out(spec_amt_piped_dir)
  );
  pipeline #(.WIDTH(FP_BITS), .DEPTH(12)) one_sub_spec_amt_pipe (
    .clk(clk),
    .in(one_sub_spec_amt),
    .out(one_sub_spec_amt_piped_dir)
  );

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
    .w(hit_normal),
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
  fp_vec3 diffuse_dir_piped;
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(2)) diffuse_dir_pipe (
    .clk(clk),
    .in(diffuse_dir),
    .out(diffuse_dir_piped)
  );
  fp_vec3 specular_dir;
  specular_reflect spec_reflector (
    .clk(clk),
    .rst(rst),
    .in_dir(ray_dir),
    .normal(hit_normal),
    .out_dir(specular_dir)
  );

  fp_vec3 specular_dir_piped;
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(10)) spec_dir_pipe (
    .clk(clk),
    .in(specular_dir),
    .out(specular_dir_piped)
  );

  fp_vec3 new_ray_dir_prenorm;
  fp_vec3_lerp lerp_dir (
    .clk(clk),
    .rst(rst),
    .v(diffuse_dir_piped),
    .w(specular_dir_piped),
    .t(spec_amt_piped_dir),
    .one_sub_t(one_sub_spec_amt_piped_dir),
    .lerped(new_ray_dir_prenorm)
  );

  fp_vec3 new_dir_unaligned;
  fp_vec3_normalize norm_dir (
    .clk(clk),
    .v(new_ray_dir_prenorm),
    .normed(new_dir_unaligned)
  );
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(REFLECT_DONE_DELAY - NEW_DIR_DELAY)) new_dir_pipe (
    .clk(clk),
    .in(new_dir_unaligned),
    .out(new_dir)
  );

  fp_vec3 hit_pos_piped;
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(35)) origin_pipe (
    .clk(clk),
    .in(hit_pos),
    .out(hit_pos_piped)
  );
  fp_vec3 hit_normal_piped;
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(34)) normal_pipe (
    .clk(clk),
    .in(hit_normal),
    .out(hit_normal_piped)
  );
  localparam fp EPSILON = 24'h370000;
  fp_vec3 scaled_normal;
  fp_vec3_scale offset_scale (
    .clk(clk),
    .rst(rst),
    .v(hit_normal_piped),
    .s(EPSILON),
    .scaled(scaled_normal)
  );

  fp_vec3_add offset_add (
    .clk(clk),
    .rst(rst),
    .v(hit_pos_piped),
    .w(scaled_normal),
    .is_sub(1'b0),
    .sum(new_origin_unaligned)
  );
  fp_vec3 new_origin_unaligned;
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(1)) new_origin_pipe (
    .clk(clk),
    .in(new_origin_unaligned),
    .out(new_origin)
  );

  fp_color ray_color_piped;
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(5)) ray_color_pipe (
    .clk(clk),
    .in(ray_color),
    .out(ray_color_piped)
  );

  fp_color extra_income_light;
  fp_vec3_mul mul_extra_income_light (
    .clk(clk),
    .v(ray_color_pipe.pipe[1]),
    .w(hit_mat.emit_color),
    .prod(extra_income_light)
  );

  fp_color income_light_piped2;
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(3)) income_light_pipe (
    .clk(clk),
    .in(income_light),
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
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(33)) new_income_light_pipe (
    .clk(clk),
    .in(new_income_light_unpiped),
    .out(new_income_light)
  );

  // Calculate new ray color.
  fp_color true_mat_color;
  fp_color mat_color_piped;
  fp_color mat_spec_color_piped;
  fp spec_amt_piped_color;
 
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(1)) mat_color_pipe (
    .clk(clk),
    .in(hit_mat.color),
    .out(mat_color_piped)
  );
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(1)) mat_spec_color_pipe (
    .clk(clk),
    .in(hit_mat.spec_color),
    .out(mat_spec_color_piped)
  );
  pipeline #(.WIDTH(FP_BITS), .DEPTH(1)) spec_amt_color_pipe (
    .clk(clk),
    .in(spec_amt),
    .out(spec_amt_piped_color)
  );

  fp_vec3_lerp lerp_true_mat_color (
    .clk(clk),
    .rst(rst),
    .v(mat_color_piped),
    .w(mat_spec_color_piped),
    .t(spec_amt_piped_color),
    .one_sub_t(one_sub_spec_amt),
    .lerped(true_mat_color)
  );

  fp_color new_color_unpiped;
  fp_vec3_mul mul_new_ray_color (
    .clk(clk),
    .rst(rst),
    .v(ray_color_piped),
    .w(true_mat_color),
    .prod(new_color_unpiped)
  );
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(31)) new_ray_color_pipe (
    .clk(clk),
    .in(new_color_unpiped),
    .out(new_color)
  );
endmodule

`default_nettype wire
