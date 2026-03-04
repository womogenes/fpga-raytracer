`default_nettype none

module ray_caster #(
  parameter WIDTH = 1280,
  parameter HEIGHT = 720
) (
  input wire clk,
  input wire rst,
  
  input camera cam,
  input wire new_ray,
  input wire ray_ready,

  output logic [10:0] pixel_h,
  output logic [9:0] pixel_v,
  output fp_vec3 ray_origin,
  output fp_vec3 ray_dir,
  output logic ray_valid,

  input wire [95:0] lfsr_seed
);
  logic [10:0] pixel_h_rsg;
  logic [9:0] pixel_v_rsg;
  logic launch_caster;
  logic maker_request_pending;

  assign launch_caster = new_ray && ray_ready && !maker_request_pending;

  ray_signal_gen #(
    .WIDTH(WIDTH),
    .HEIGHT(HEIGHT)
  ) rsg (
    .clk(clk),
    .rst(rst),
    .new_ray(launch_caster),

    .pixel_h(pixel_h_rsg),
    .pixel_v(pixel_v_rsg)
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      maker_request_pending <= 1'b0;
    end else begin
      if (launch_caster) begin
        maker_request_pending <= 1'b1;
      end
      if (ray_valid) begin
        maker_request_pending <= 1'b0;
      end
    end
  end

  ray_maker #(
    .WIDTH(WIDTH),
    .HEIGHT(HEIGHT)
  ) maker (
    .clk(clk),
    .rst(rst),

    .cam(cam),
    .pixel_h_in(pixel_h_rsg),
    .pixel_v_in(pixel_v_rsg),
    .new_ray(launch_caster),

    .ray_origin(ray_origin),
    .ray_dir(ray_dir),
    .ray_valid(ray_valid),

    .pixel_h_out(pixel_h),
    .pixel_v_out(pixel_v),

    .lfsr_seed(lfsr_seed)
  );
endmodule

`default_nettype wire
