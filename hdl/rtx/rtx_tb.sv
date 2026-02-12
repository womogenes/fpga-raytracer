`default_nettype none

// Testbench for rtx
// All this does is wrap rtx but provide scene buffer as well

module rtx_tb #(
  parameter WIDTH = 1280,
  parameter HEIGHT = 720
) (
  input wire clk,
  input wire rst,
  input camera cam,
  input wire [$clog2(MAX_NUM_OBJS)-1:0] num_objs,
  input wire [7:0] max_bounces,

  output logic [15:0] rtx_pixel,
  output logic [10:0] pixel_h,
  output logic [9:0] pixel_v,
  output logic ray_done          // i.e. pixel_color valid
);
  object obj;
  logic [7:0] mat_dict_idx;
  material mat_dict_mat;

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

  rtx #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) my_rtx (
    .clk(clk),
    .rst(rst),
    .cam(cam),

    .rtx_pixel(rtx_pixel),
    .pixel_h(pixel_h),
    .pixel_v(pixel_v),
    .ray_done(ray_done),

    // Max bounce limit
    .max_bounces(max_bounces),

    // Scene buffer wires
    .num_objs(num_objs),
    .obj(obj),

    // Material dictionary wires
    .mat_dict_idx(mat_dict_idx),
    .mat_dict_mat(mat_dict_mat)
  );

endmodule

`default_nettype wire
