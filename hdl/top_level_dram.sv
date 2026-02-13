`default_nettype none //  prevents system from inferring an undeclared logic (good practice)

`define FPATH(X) `"X`"

module top_level (
  // Genesys 2 provides a 200MHz differential system clock (SYSCLK_P/N).
  // We derive a local 100MHz clock from it to keep the rest of the design
  // (UART baud assumptions + existing clock wizards) unchanged.
  input wire sysclk_p,
  input wire sysclk_n,
  input wire [7:0] sw, // all 8 input slide switches

  input wire [4:0] btn, // all four momentary button switches
  output logic [7:0] led, // 8 green output LEDs (located right above switches)

  // HDMI output signals (positives/negatives are {blue, green, red} lanes)
  output logic [2:0] hdmi_tx_p,
  output logic [2:0] hdmi_tx_n,
  output logic hdmi_clk_p,
  output logic hdmi_clk_n,

  // SDRAM (DDR3) ports (lower 16-bit of Genesys2's 32-bit DDR3 interface)
  inout wire [15:0] ddr3_dq, // data input/output
  inout wire [1:0] ddr3_dqs_n, // differential strobe (negative)
  inout wire [1:0] ddr3_dqs_p, // differential strobe (positive)
  output wire [13:0] ddr3_addr, // address
  output wire [2:0] ddr3_ba, // bank address
  output wire ddr3_ras_n, // row active strobe
  output wire ddr3_cas_n, // column active strobe
  output wire ddr3_we_n, // write enable
  output wire ddr3_reset_n, // reset (active low)
  output wire ddr3_clk_p, // differential clock (p)
  output wire ddr3_clk_n, // differential clock (n)
  output wire ddr3_clke, // clock enable
  output wire [1:0] ddr3_dm, // data mask
  output wire ddr3_odt // on-die termination
);
  wire clk_100mhz;
  wire sysclk_locked;

  clkwiz sysclk_wiz (
    .sysclk_p   (sysclk_p),
    .sysclk_n   (sysclk_n),
    .clk_100mhz (clk_100mhz),
    .locked     (sysclk_locked)
  );

  // btn[0] acts as reset (same convention as other tops)
  logic sys_rst_btn;
  assign sys_rst_btn = btn[0];

  // HDMI clocking (74.25MHz pixel + 371.25MHz TMDS/5x clock for 720p60)
  logic clk_pixel;
  logic clk_5x;
  logic hdmi_clk_locked;

  cw_hdmi_clk_wiz hdmi_clk_wiz (
    .sysclk   (clk_100mhz),
    // Match `top_level_rtx.sv`: don't reset the MMCM from the button.
    // If `btn[0]` polarity is ever wrong (or bounces), holding MMCM reset can
    // prevent any HDMI output from ever appearing.
    .reset    (1'b0),
    .clk_pixel(clk_pixel),
    .clk_tmds (clk_5x),
    .locked   (hdmi_clk_locked)
  );

  // Reset handling:
  // - synchronize btn[0] into the pixel clock domain (avoids metastability)
  // - allow quick polarity/bypass debug using switches:
  //   - sw[1]=1 inverts btn[0] (useful if button is active-low)
  //   - sw[0]=1 forces reset deasserted (useful if reset is stuck)
  logic rst_btn_pix_ff0;
  logic rst_btn_pix_ff1;
  always_ff @(posedge clk_pixel) begin
    rst_btn_pix_ff0 <= sys_rst_btn;
    rst_btn_pix_ff1 <= rst_btn_pix_ff0;
  end

  logic sys_rst_btn_pix;
  assign sys_rst_btn_pix = rst_btn_pix_ff1;

  logic sys_rst_btn_pix_pol;
  assign sys_rst_btn_pix_pol = sw[1] ? ~sys_rst_btn_pix : sys_rst_btn_pix;

  logic sys_rst;
  assign sys_rst = sw[0] ? 1'b0 : sys_rst_btn_pix_pol;

  // --- DDR3 + framebuffer readout ---
  // sw[2]=0: known-good HDMI solid fill (isolate HDMI)
  // sw[2]=1: show DRAM contents (raw framebuffer reads)
  //
  // Note: DDR3 I/O standards in `xdc/top_level.xdc` were adjusted to remove the
  // *_T_DCI variants; those settings were preventing the FPGA from reaching DONE
  // during configuration on this board.
  logic clk_controller;
  logic clk_ddr3;
  logic clk_ddr3_90;
  logic clk_camera;
  logic lab06_clk_locked;

  // Use the existing internal 100MHz clock as our "rtx/write-side" clock.
  // (We keep rtx_valid=0 for now, so we won't write.)
  wire clk_rtx;
  assign clk_rtx = clk_100mhz;

  lab06_clk_wiz ddr3_clk_wiz (
    .reset          (1'b0),
    .clk_in1        (clk_100mhz),
    .clk_controller (clk_controller),
    .clk_ddr3       (clk_ddr3),
    .clk_ddr3_90    (clk_ddr3_90),
    .clk_camera     (clk_camera),
    .clk_xc         (), // unused
    .clk_passthrough(), // unused
    .locked         (lab06_clk_locked)
  );

  // Sync the (pixel-domain) sys_rst into the DDR controller clock domain.
  logic rst_ctrl_ff0;
  logic rst_ctrl_ff1;
  always_ff @(posedge clk_controller) begin
    rst_ctrl_ff0 <= sys_rst;
    rst_ctrl_ff1 <= rst_ctrl_ff0;
  end
  logic sys_rst_controller;
  assign sys_rst_controller = rst_ctrl_ff1;

  // Sync reset into the write-side clock domain (even though we won't write yet).
  logic rst_rtx_ff0;
  logic rst_rtx_ff1;
  always_ff @(posedge clk_rtx) begin
    rst_rtx_ff0 <= sys_rst;
    rst_rtx_ff1 <= rst_rtx_ff0;
  end
  logic sys_rst_rtx;
  assign sys_rst_rtx = rst_rtx_ff1;

  logic [15:0] frame_buff_dram;
  logic [5:0] dram_debug;
  logic [4:0] dram_calib_state;

  high_definition_frame_buffer highdef_fb (
    // Write-side (idle)
    .clk_rtx      (clk_rtx),
    .sys_rst_rtx  (sys_rst_rtx),
    .rtx_valid    (1'b0),
    .rtx_pixel    (16'h0000),
    .rtx_h_count  (11'd0),
    .rtx_v_count  (10'd0),
    .rtx_overwrite(1'b0),

    // Read-side (HDMI)
    .clk_pixel       (clk_pixel),
    .sys_rst_pixel   (sys_rst),
    .active_draw_hdmi(active_draw_hdmi),
    .h_count_hdmi    (h_count_hdmi),
    .v_count_hdmi    (v_count_hdmi),
    .frame_buff_dram (frame_buff_dram),

    // DDR3 clocks/resets
    .clk_controller  (clk_controller),
    .clk_ddr3        (clk_ddr3),
    .clk_ddr3_90     (clk_ddr3_90),
    .i_ref_clk       (clk_camera),
    .i_rst           (sys_rst_controller),
    .ddr3_clk_locked (lab06_clk_locked),

    .debug(dram_debug),
    .calib_state(dram_calib_state),

    // DDR3 physical interface
    .ddr3_dq      (ddr3_dq),
    .ddr3_dqs_n   (ddr3_dqs_n),
    .ddr3_dqs_p   (ddr3_dqs_p),
    .ddr3_addr    (ddr3_addr),
    .ddr3_ba      (ddr3_ba),
    .ddr3_ras_n   (ddr3_ras_n),
    .ddr3_cas_n   (ddr3_cas_n),
    .ddr3_we_n    (ddr3_we_n),
    .ddr3_reset_n (ddr3_reset_n),
    .ddr3_clk_p   (ddr3_clk_p),
    .ddr3_clk_n   (ddr3_clk_n),
    .ddr3_clke    (ddr3_clke),
    .ddr3_dm      (ddr3_dm),
    .ddr3_odt     (ddr3_odt)
  );

  logic [10:0] h_count_hdmi;
  logic [9:0] v_count_hdmi;
  logic h_sync;
  logic v_sync;
  logic active_draw_hdmi;
  logic new_frame;
  logic [5:0] frame_count;

  video_sig_gen vsg (
    .pixel_clk  (clk_pixel),
    .rst        (sys_rst),
    .h_count    (h_count_hdmi),
    .v_count    (v_count_hdmi),
    .v_sync     (v_sync),
    .h_sync     (h_sync),
    .active_draw(active_draw_hdmi),
    .new_frame  (new_frame),
    .frame_count(frame_count)
  );

  // Solid fill: RGB = 0d7a31 (known-good test pattern)
  localparam logic [7:0] SOLID_R = 8'h0d;
  localparam logic [7:0] SOLID_G = 8'h7a;
  localparam logic [7:0] SOLID_B = 8'h31;

  logic [7:0] red;
  logic [7:0] green;
  logic [7:0] blue;

  always_comb begin
    if (active_draw_hdmi) begin
      if (sw[2]) begin
        // DRAM visualization mode.
        // If the DDR clock wizard isn't locked, show a loud red screen so it's
        // obvious we're in DRAM mode but DDR clocks aren't running.
        if (!lab06_clk_locked) begin
          red = 8'hff;
          green = 8'h00;
          blue = 8'h00;
        end else begin
          // RGB565 -> RGB888 (simple zero-extend)
          red = {frame_buff_dram[4:0], 3'b000};
          green = {frame_buff_dram[10:5], 2'b00};
          blue = {frame_buff_dram[15:11], 3'b000};
        end
      end else begin
        red = SOLID_R;
        green = SOLID_G;
        blue = SOLID_B;
      end
    end else begin
      red = 8'h00;
      green = 8'h00;
      blue = 8'h00;
    end
  end

  logic [9:0] tmds_10b [0:2];
  logic tmds_signal [2:0];

  tmds_encoder tmds_blue (
    .clk(clk_pixel),
    .rst(sys_rst),
    .video_data(blue),
    .control({v_sync, h_sync}),
    .video_enable(active_draw_hdmi),
    .tmds(tmds_10b[0])
  );

  tmds_encoder tmds_green (
    .clk(clk_pixel),
    .rst(sys_rst),
    .video_data(green),
    .control(2'b0),
    .video_enable(active_draw_hdmi),
    .tmds(tmds_10b[1])
  );

  tmds_encoder tmds_red (
    .clk(clk_pixel),
    .rst(sys_rst),
    .video_data(red),
    .control(2'b0),
    .video_enable(active_draw_hdmi),
    .tmds(tmds_10b[2])
  );

  tmds_serializer blue_ser (
    .clk_pixel(clk_pixel),
    .clk_5x(clk_5x),
    .rst(sys_rst),
    .tmds_in(tmds_10b[0]),
    .tmds_out(tmds_signal[0])
  );

  tmds_serializer green_ser (
    .clk_pixel(clk_pixel),
    .clk_5x(clk_5x),
    .rst(sys_rst),
    .tmds_in(tmds_10b[1]),
    .tmds_out(tmds_signal[1])
  );

  tmds_serializer red_ser (
    .clk_pixel(clk_pixel),
    .clk_5x(clk_5x),
    .rst(sys_rst),
    .tmds_in(tmds_10b[2]),
    .tmds_out(tmds_signal[2])
  );

  OBUFDS OBUFDS_blue  (.I(tmds_signal[0]), .O(hdmi_tx_p[0]), .OB(hdmi_tx_n[0]));
  OBUFDS OBUFDS_green (.I(tmds_signal[1]), .O(hdmi_tx_p[1]), .OB(hdmi_tx_n[1]));
  OBUFDS OBUFDS_red   (.I(tmds_signal[2]), .O(hdmi_tx_p[2]), .OB(hdmi_tx_n[2]));
  OBUFDS OBUFDS_clock (.I(clk_pixel),      .O(hdmi_clk_p),   .OB(hdmi_clk_n));

  // LED debug:
  // Default (sw[7]=0): same feel as the test top.
  // - led[7]: sysclk MMCM locked
  // - led[6]: HDMI MMCM locked
  // - led[5]: DDR3 clock wizard locked
  // - led[4]: sw[2] (DRAM display mode)
  // - led[3:0]: frame counter low bits
  //
  // Debug (sw[7]=1): show DDR3 pipeline health from `high_definition_frame_buffer`.
  // - led[7]: sysclk MMCM locked
  // - led[6]: HDMI MMCM locked
  // - led[5:0]: highdef_fb.debug (see `high_definition_frame_buffer.sv`)
  // - with sw[6]=1, show calibration state machine instead:
  //   led[5]=calib_complete, led[4:0]=state_calibrate
  logic [7:0] led_normal;
  logic [7:0] led_debug;
  logic [7:0] led_calib;
  assign led_normal = {sysclk_locked, hdmi_clk_locked, lab06_clk_locked, sw[2], frame_count[3:0]};
  assign led_debug = {sysclk_locked, hdmi_clk_locked, dram_debug};
  assign led_calib = {sysclk_locked, hdmi_clk_locked, dram_debug[5], dram_calib_state};
  assign led = sw[7] ? (sw[6] ? led_calib : led_debug) : led_normal;

endmodule
