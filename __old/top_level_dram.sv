`timescale 1ns / 1ps
`default_nettype none

module top_level(
  input wire      clk_100mhz,
  output logic [15:0] led,
  input wire [15:0]   sw,
  input wire [3:0]  btn,
  output logic [2:0]  rgb0,
  output logic [2:0]  rgb1,
  // seven segment
  output logic [3:0]  ss0_an,//anode control for upper four digits of seven-seg display
  output logic [3:0]  ss1_an,//anode control for lower four digits of seven-seg display
  output logic [6:0]  ss0_c, //cathode controls for the segments of upper four digits
  output logic [6:0]  ss1_c, //cathod controls for the segments of lower four digits
  // hdmi port
  output logic [2:0]  hdmi_tx_p, //hdmi output signals (positives) (blue, green, red)
  output logic [2:0]  hdmi_tx_n, //hdmi output signals (negatives) (blue, green, red)
  output logic    hdmi_clk_p, hdmi_clk_n, //differential hdmi clock
  // uart
  input wire uart_rxd, // UART computer->FPGA
  // New for week 6: SDRAM (DDR3) ports
  inout wire [15:0]   ddr3_dq, //data input/output
  inout wire [1:0]  ddr3_dqs_n, //data input/output differential strobe (negative)
  inout wire [1:0]  ddr3_dqs_p, //data input/output differential strobe (positive)
  output wire [13:0]  ddr3_addr, //address
  output wire [2:0]   ddr3_ba, //bank address
  output wire     ddr3_ras_n, //row active strobe
  output wire     ddr3_cas_n, //column active strobe
  output wire     ddr3_we_n, //write enable
  output wire     ddr3_reset_n, //reset (active low!!!)
  output wire     ddr3_clk_p, //general differential clock (p)
  output wire     ddr3_clk_n, //general differential clock (n)
  output wire     ddr3_clke, //clock enable
  output wire [1:0]   ddr3_dm, //data mask
  output wire     ddr3_odt //on-die termination (helps impedance match)
);

  // shut up those RGBs
  assign rgb1 = 0; //rgb0 used for camera status

  // Clock and Reset Signals
  logic      sys_rst_camera;
  logic      sys_rst_pixel;
  logic      sys_rst_controller;

  logic      clk_camera;
  logic      clk_pixel;
  logic      clk_5x;
  logic      clk_xc;

  logic clk_camera_locked;
  logic clk_pixel_locked;

  logic      clk_100_passthrough;

  // clocking wizards to generate the clock speeds we need for our different domains
  // clk_camera: 200MHz, fast enough to comfortably sample the cameera's PCLK (50MHz)
  cw_hdmi_clk_wiz wizard_hdmi(
    .sysclk(clk_100_passthrough),
    .clk_pixel(clk_pixel),
    .clk_tmds(clk_5x),
    .reset(0),
    .locked()
  );

  logic clk_controller;
  logic clk_ddr3;
  logic i_ref_clk;
  logic clk_ddr3_90;

  logic lab06_clk_locked;

  lab06_clk_wiz lcw(
    .reset(btn[0]),
    .clk_in1(clk_100mhz),
    .clk_camera(clk_camera),
    .clk_xc(clk_xc),
    .clk_passthrough(clk_100_passthrough),
    .clk_controller(clk_controller),
    .clk_ddr3(clk_ddr3),
    .clk_ddr3_90(clk_ddr3_90),
    .locked(lab06_clk_locked)
  );

  assign i_ref_clk = clk_camera;

  (* mark_debug = "true" *) wire ddr3_clk_locked;

  assign ddr3_clk_locked = lab06_clk_locked;
  assign clk_camera_locked = lab06_clk_locked;

  // assign camera's xclk to pmod port: drive the operating clock of the camera!
  // this port also is specifically set to high drive by the XDC file.
  // assign cam_xclk = clk_xc;

  // video signal generator signals
  logic         h_sync_hdmi;
  logic         v_sync_hdmi;
  logic [10:0]  h_count_hdmi;
  logic [9:0]   v_count_hdmi;
  logic         active_draw_hdmi;
  logic         new_frame_hdmi;
  logic [5:0]   frame_count_hdmi;

  // rgb output values
  logic [7:0]   red, green, blue;

  // ** Handling input from the camera **
  logic       sys_rst_camera_buf [1:0];
  logic       sys_rst_pixel_buf [1:0];
  logic       sys_rst_controller_buf [1:0];

  always_ff @(posedge clk_pixel) begin
    sys_rst_pixel_buf <= {btn[0], sys_rst_pixel_buf[1]};
  end
  assign sys_rst_pixel = sys_rst_pixel_buf[0];

  always_ff @(posedge clk_controller )begin
    sys_rst_controller_buf <= {btn[0], sys_rst_controller_buf[1]};
  end
  assign sys_rst_controller = sys_rst_controller_buf[0];

  logic [10:0]  camera_h_count;
  logic [9:0]   camera_v_count;
  logic [15:0]  camera_pixel;
  logic         camera_valid;

  // rtx requires a scene buffer
  object scene_buf_obj;

  scene_buffer #(.INIT_FILE("data/scene_buffer.mem")) scene_buf (
    .clk(clk),
    .rst(rst),
    .obj(scene_buf_obj)
  );

  // uart flashing of scene buffer (among other things)

  color8 rtx_pixel;
  rtx (
    .clk(clk_camera),
    .rst(sys_rst_camera),

    .pixel_color(rtx_pixel),
    .pixel_h(camera_h_count),
    .pixel_v(camera_v_count),
    .ray_done(camera_valid),

    .obj(scene_buf_obj)
  );

  assign camera_pixel = {
    rtx_pixel.r[7:3],
    rtx_pixel.g[7:2],
    rtx_pixel.b[7:3]
  };

  // TODO: allow UART reflashing of scene buffer

  // Two ways to store a frame buffer:
  // 1. down-sampled with BRAM; same as week 05
  // 2. Full-quality with SDRAM (DDR3); the new pipeline this week!
  
  // (deleted BRAM logic)

  // 2. The New Way: write memory to DRAM and read it
  //  out, over a couple AXI-Stream data pipelines.

  // the high_definition_frame_buffer module does all of the
  // "top-level wiring" for the FIFOs, the stacker and unstacker
  // traffic generator, and the IP memory controller.
  // it needs:
  // 1. camera data input, to write to the frame buffer
  // 2. output connection to the HDMI output
  // 3. the wires that connect to our DRAM chip

  logic [15:0] frame_buff_dram;

  high_definition_frame_buffer highdef_fb(
    // Input data from camera/pixel reconstructor
    .clk_camera    (clk_camera),
    .sys_rst_camera  (sys_rst_camera),
    .camera_valid  (camera_valid),
    .camera_pixel  (camera_pixel[15:0]),
    .camera_h_count  (camera_h_count[10:0]),
    .camera_v_count  (camera_v_count[9:0]),
    
    // Output data to HDMI display pipeline
    .clk_pixel     (clk_pixel),
    .sys_rst_pixel   (sys_rst_pixel),
    .active_draw_hdmi(active_draw_hdmi),
    .h_count_hdmi  (h_count_hdmi[10:0]),
    .v_count_hdmi  (v_count_hdmi[9:0]),
    .frame_buff_dram (frame_buff_dram[15:0]),

    // Clock/reset signals for UberDDR3 controller
    .clk_controller  (clk_controller),
    .clk_ddr3    (clk_ddr3),
    .clk_ddr3_90   (clk_ddr3_90),
    .i_ref_clk     (i_ref_clk),
    .i_rst       (sys_rst_controller),
    .ddr3_clk_locked (ddr3_clk_locked),

    // Bus wires to connect FPGA to SDRAM chip
    .ddr3_dq     (ddr3_dq[15:0]),
    .ddr3_dqs_n    (ddr3_dqs_n[1:0]),
    .ddr3_dqs_p    (ddr3_dqs_p[1:0]),
    .ddr3_addr     (ddr3_addr[13:0]),
    .ddr3_ba     (ddr3_ba[2:0]),
    .ddr3_ras_n    (ddr3_ras_n),
    .ddr3_cas_n    (ddr3_cas_n),
    .ddr3_we_n     (ddr3_we_n),
    .ddr3_reset_n  (ddr3_reset_n),
    .ddr3_clk_p    (ddr3_clk_p),
    .ddr3_clk_n    (ddr3_clk_n),
    .ddr3_clke     (ddr3_clke),
    .ddr3_dm     (ddr3_dm[1:0]),
    .ddr3_odt    (ddr3_odt)
  );
  
  // display some activity signals on the LEDs
  assign led[15] = highdef_fb.memrequest_busy;
  assign led[14] = highdef_fb.memrequest_complete;
  assign led[13] = highdef_fb.memrequest_resp_data[4];
  assign led[12] = highdef_fb.memrequest_en;
  assign led[11] = highdef_fb.memrequest_write_enable;
  assign led[10] = highdef_fb.memrequest_addr[0];
  assign led[9] = highdef_fb.display_memclk_axis_tvalid;
  assign led[8] = highdef_fb.display_memclk_axis_tready;
  assign led[7] = highdef_fb.camera_memclk_axis_tvalid;
  assign led[6] = highdef_fb.camera_memclk_axis_tready;

  // NEW DRAM STUFF ENDS HERE: below here should look familiar from last week!

  // split fame_buff into 3 8 bit color channels (5:6:5 adjusted accordingly)
  // remapped frame_buffer outputs with 8 bits for r, g, b
  logic [7:0] fb_red, fb_green, fb_blue;
  always_ff @(posedge clk_pixel) begin
    fb_red <= {frame_buff_dram[15:11], 3'b0};
    fb_green <= {frame_buff_dram[10:5],  2'b0};
    fb_blue <= {frame_buff_dram[4:0], 3'b0};
  end
  // Pixel Processing pre-HDMI output

  // HDMI video signal generator
  video_sig_gen vsg(
    .pixel_clk(clk_pixel),
    .rst(sys_rst_pixel),
    .h_count(h_count_hdmi),
    .v_count(v_count_hdmi),
    .v_sync(v_sync_hdmi),
    .h_sync(h_sync_hdmi),
    .new_frame(new_frame_hdmi),
    .active_draw(active_draw_hdmi),
    .frame_count(frame_count_hdmi)
  );

  // HDMI Output: just like before!

  logic [9:0] tmds_10b [0:2]; //output of each TMDS encoder!
  logic     tmds_signal [2:0]; //output of each TMDS serializer!

  //three tmds_encoders (blue, green, red)
  //note green should have no control signal like red
  //the blue channel DOES carry the two sync signals:
  //  * control[0] = horizontal sync signal
  //  * control[1] = vertical sync signal

  tmds_encoder tmds_red(
    .clk(clk_pixel),
    .rst(sys_rst_pixel),
    .video_data(fb_red),
    .control(2'b0),
    .video_enable(active_draw_hdmi),
    .tmds(tmds_10b[2])
  );
  tmds_encoder tmds_green(
    .clk(clk_pixel),
    .rst(sys_rst_pixel),
    .video_data(fb_green),
    .control(2'b0),
    .video_enable(active_draw_hdmi),
    .tmds(tmds_10b[1])
  );
  tmds_encoder tmds_blue(
    .clk(clk_pixel),
    .rst(sys_rst_pixel),
    .video_data(fb_blue),
    .control({v_sync_hdmi,h_sync_hdmi}),
    .video_enable(active_draw_hdmi),
    .tmds(tmds_10b[0])
  );


  //three tmds_serializers (blue, green, red):
  //MISSING: two more serializers for the green and blue tmds signals.
  tmds_serializer red_ser(
    .clk_pixel(clk_pixel),
    .clk_5x(clk_5x),
    .rst(sys_rst_pixel),
    .tmds_in(tmds_10b[2]),
    .tmds_out(tmds_signal[2])
  );
  tmds_serializer green_ser(
    .clk_pixel(clk_pixel),
    .clk_5x(clk_5x),
    .rst(sys_rst_pixel),
    .tmds_in(tmds_10b[1]),
    .tmds_out(tmds_signal[1])
  );
  tmds_serializer blue_ser(
    .clk_pixel(clk_pixel),
    .clk_5x(clk_5x),
    .rst(sys_rst_pixel),
    .tmds_in(tmds_10b[0]),
    .tmds_out(tmds_signal[0])
  );

  //output buffers generating differential signals:
  //three for the r,g,b signals and one that is at the pixel clock rate
  //the HDMI receivers use recover logic coupled with the control signals asserted
  //during blanking and sync periods to synchronize their faster bit clocks off
  //of the slower pixel clock (so they can recover a clock of about 742.5 MHz from
  //the slower 74.25 MHz clock)
  OBUFDS OBUFDS_blue (.I(tmds_signal[0]), .O(hdmi_tx_p[0]), .OB(hdmi_tx_n[0]));
  OBUFDS OBUFDS_green(.I(tmds_signal[1]), .O(hdmi_tx_p[1]), .OB(hdmi_tx_n[1]));
  OBUFDS OBUFDS_red  (.I(tmds_signal[2]), .O(hdmi_tx_p[2]), .OB(hdmi_tx_n[2]));
  OBUFDS OBUFDS_clock(.I(clk_pixel), .O(hdmi_clk_p), .OB(hdmi_clk_n));

endmodule // top_level


`default_nettype wire
