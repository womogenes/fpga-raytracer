`default_nettype none

module ray_intersector_scene_tb (
  input wire clk,
  input wire rst,
  input fp_vec3 ray_origin,
  input fp_vec3 ray_dir,
  input wire ray_valid,
  input wire [$clog2(MAX_NUM_OBJS)-1:0] num_objs,

  output logic [7:0] hit_mat_idx,
  output fp_vec3 hit_pos,
  output fp_vec3 hit_normal,
  output fp hit_dist,
  output logic hit_any,
  output logic hit_valid,
  output logic [7:0] obj_mat_idx_dbg,
  output logic [7:0] obj_intx_mat_idx_dbg,
  output logic ray_valid_piped_dbg,
  output logic processing_obj_dbg,
  output logic sphere_hit_dbg
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

  ray_intersector dut (
    .clk(clk),
    .rst(rst),
    .ray_origin(ray_origin),
    .ray_dir(ray_dir),
    .ray_valid(ray_valid),
    .hit_mat_idx(hit_mat_idx),
    .hit_pos(hit_pos),
    .hit_normal(hit_normal),
    .hit_dist(hit_dist),
    .hit_any(hit_any),
    .hit_valid(hit_valid),
    .num_objs(num_objs),
    .obj(obj)
  );

  assign obj_mat_idx_dbg = obj.mat_idx;
  assign obj_intx_mat_idx_dbg = dut.obj_intx_mat_idx;
  assign ray_valid_piped_dbg = dut.ray_valid_piped;
  assign processing_obj_dbg = dut.processing_obj;
  assign sphere_hit_dbg = dut.sphere_intx_hit;
endmodule

`default_nettype wire
