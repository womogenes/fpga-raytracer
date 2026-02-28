`default_nettype none

module ray_maker_probe_tb #(
  parameter WIDTH = 1280,
  parameter HEIGHT = 720
) (
  input wire clk,
  input wire rst,
  input camera cam,
  input wire [10:0] pixel_h_in,
  input wire [9:0] pixel_v_in,
  input wire new_ray,
  input wire [95:0] lfsr_seed,

  output fp_vec3 ray_origin,
  output fp_vec3 ray_dir,
  output logic ray_valid,
  output logic [10:0] pixel_h_out,
  output logic [9:0] pixel_v_out
);
  ray_maker #(
    .WIDTH(WIDTH),
    .HEIGHT(HEIGHT)
  ) dut (
    .clk(clk),
    .rst(rst),
    .cam(cam),
    .pixel_h_in(pixel_h_in),
    .pixel_v_in(pixel_v_in),
    .new_ray(new_ray),
    .ray_origin(ray_origin),
    .ray_dir(ray_dir),
    .ray_valid(ray_valid),
    .pixel_h_out(pixel_h_out),
    .pixel_v_out(pixel_v_out),
    .lfsr_seed(lfsr_seed)
  );
endmodule

`default_nettype wire
