`default_nettype none

module ray_intersector_multi_tb (
  input wire clk,
  input wire rst,
  input wire [$clog2(MAX_NUM_OBJS)-1:0] num_objs,

  input fp_vec3 ray0_origin,
  input fp_vec3 ray0_dir,
  input wire ray0_valid,
  output logic [7:0] hit0_mat_idx,
  output fp_vec3 hit0_pos,
  output logic hit0_any,
  output logic hit0_valid,

  input fp_vec3 ray1_origin,
  input fp_vec3 ray1_dir,
  input wire ray1_valid,
  output logic [7:0] hit1_mat_idx,
  output fp_vec3 hit1_pos,
  output logic hit1_any,
  output logic hit1_valid
);
  object obj;

  scene_buffer #(.INIT_FILE("data/test_ray_intersector_scene_buffer.mem")) scene_buf (
    .clk(clk),
    .rst(rst),
    .num_objs(num_objs),
    .flash_obj_wen(1'b0),
    .flash_obj_idx('0),
    .flash_obj_data('0),
    .obj(obj)
  );

  ray_intersector dut0 (
    .clk(clk),
    .rst(rst),
    .ray_origin(ray0_origin),
    .ray_dir(ray0_dir),
    .ray_valid(ray0_valid),
    .hit_mat_idx(hit0_mat_idx),
    .hit_pos(hit0_pos),
    .hit_normal(),
    .hit_dist(),
    .hit_any(hit0_any),
    .hit_valid(hit0_valid),
    .num_objs(num_objs),
    .obj(obj)
  );

  ray_intersector dut1 (
    .clk(clk),
    .rst(rst),
    .ray_origin(ray1_origin),
    .ray_dir(ray1_dir),
    .ray_valid(ray1_valid),
    .hit_mat_idx(hit1_mat_idx),
    .hit_pos(hit1_pos),
    .hit_normal(),
    .hit_dist(),
    .hit_any(hit1_any),
    .hit_valid(hit1_valid),
    .num_objs(num_objs),
    .obj(obj)
  );
endmodule

`default_nettype wire
