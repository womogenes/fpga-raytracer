`default_nettype none

module ray_reflector_tb (
  input wire clk,
  input wire rst,
  input fp_vec3 ray_dir,
  input fp_color ray_color,
  input fp_color income_light,
  input fp_vec3 hit_pos,
  input fp_vec3 hit_normal,
  input wire [7:0] hit_mat_idx,
  input wire hit_valid,
  input wire [95:0] lfsr_seed,

  output fp_vec3 new_dir,
  output fp_vec3 new_origin,
  output fp_color new_color,
  output fp_color new_income_light,
  output logic reflect_done,
  output logic [7:0] mat_dict_idx
);
  material mat_dict_mat;

  material_dictionary #(.INIT_FILE("data/test_ray_reflector_mat_dict.mem")) mat_dict (
    .clk(clk),
    .rst(rst),
    .flash_mat_wen(1'b0),
    .flash_mat_idx('0),
    .flash_mat_data('0),
    .mat_idx(mat_dict_idx),
    .mat(mat_dict_mat)
  );

  ray_reflector dut (
    .clk(clk),
    .rst(rst),
    .ray_dir(ray_dir),
    .ray_color(ray_color),
    .income_light(income_light),
    .hit_pos(hit_pos),
    .hit_normal(hit_normal),
    .hit_mat_idx(hit_mat_idx),
    .hit_valid(hit_valid),
    .new_dir(new_dir),
    .new_origin(new_origin),
    .new_color(new_color),
    .new_income_light(new_income_light),
    .reflect_done(reflect_done),
    .mat_dict_idx(mat_dict_idx),
    .mat_dict_mat(mat_dict_mat),
    .lfsr_seed(lfsr_seed)
  );
endmodule

`default_nettype wire
