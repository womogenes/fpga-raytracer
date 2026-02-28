`default_nettype none

module ray_tracer_tb (
  input wire clk,
  input wire rst,
  input fp_vec3 ray_origin,
  input fp_vec3 ray_dir,
  input wire ray_valid,
  input wire [$clog2(MAX_NUM_OBJS)-1:0] num_objs,
  input object obj,
  input wire [7:0] max_bounces,
  input wire [95:0] lfsr_seed,

  output logic ray_done,
  output fp_color pixel_color,
  output logic [7:0] mat_dict_idx
);
  material mat_dict_mat;

  material_dictionary #(.INIT_FILE("data/test_ray_tracer_mat_dict.mem")) mat_dict (
    .clk(clk),
    .rst(rst),
    .flash_mat_wen(1'b0),
    .flash_mat_idx('0),
    .flash_mat_data('0),
    .mat_idx(mat_dict_idx),
    .mat(mat_dict_mat)
  );

  ray_tracer dut (
    .clk(clk),
    .rst(rst),
    .pixel_h_in('0),
    .pixel_v_in('0),
    .ray_origin(ray_origin),
    .ray_dir(ray_dir),
    .ray_valid(ray_valid),
    .ray_done(ray_done),
    .pixel_color(pixel_color),
    .pixel_h_out(),
    .pixel_v_out(),
    .num_objs(num_objs),
    .obj(obj),
    .mat_dict_idx(mat_dict_idx),
    .mat_dict_mat(mat_dict_mat),
    .max_bounces(max_bounces),
    .lfsr_seed(lfsr_seed)
  );
endmodule

`default_nettype wire
