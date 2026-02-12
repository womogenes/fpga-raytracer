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
  output logic hdmi_clk_n
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

  // Solid fill: RGB = 0d7a31
  localparam logic [7:0] SOLID_R = 8'h0d;
  localparam logic [7:0] SOLID_G = 8'h7a;
  localparam logic [7:0] SOLID_B = 8'h31;

  logic [7:0] red;
  logic [7:0] green;
  logic [7:0] blue;

  always_comb begin
    if (active_draw_hdmi) begin
      red = SOLID_R;
      green = SOLID_G;
      blue = SOLID_B;
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
  // - led[7]: sysclk MMCM locked
  // - led[6]: HDMI MMCM locked
  // - led[5:0]: frame counter (bit5 blinks ~0.5Hz if video is running)
  assign led = {sysclk_locked, hdmi_clk_locked, frame_count};

endmodule
