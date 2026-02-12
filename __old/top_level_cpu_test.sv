`default_nettype none //  prevents system from inferring an undeclared logic (good practice)

`define FPATH(X) `"X`"

module top_level (
  input wire clk_100mhz, // crystal reference clock
  input wire [15:0] sw, // all 16 input slide switches

  input wire [3:0] btn, // all four momentary button switches
  output logic [15:0] led, // 16 green output LEDs (located right above switches)
  output logic [2:0] rgb0, // rgb led
  output logic [2:0] rgb1, // rgb led

  // seven-segment outputs
  output logic [3:0] ss0_an,
  output logic [3:0] ss1_an,
  output logic [6:0] ss0_c,
  output logic [6:0] ss1_c,

  // HDMI, UART peripherals etc
  output logic [2:0] hdmi_tx_p, // hdmi output signals (positives) (blue, green, red)
  output logic [2:0] hdmi_tx_n, // hdmi output signals (negatives) (blue, green, red)
  output logic hdmi_clk_p, hdmi_clk_n, // differential hdmi clock
  input wire uart_rxd // UART computer->FPGA
);
  // shut up those rgb LEDs (active high):
  assign rgb1 = 0;
  assign rgb0 = 0;

  // buffered clock signal (we need this apparently)
  wire clk_100mhz_buffered;
  IBUF clkin1_ibufg (
    .I(clk_100mhz),
    .O(clk_100mhz_buffered)
  );
 
  // have btn[0] control system reset
  logic sys_rst;
  assign sys_rst = btn[0]; // reset is btn[0]

  // ==== PROCESSOR =====
  logic cpu_mem_valid;
  logic cpu_mem_instr;
  logic [31:0] cpu_mem_addr;
  logic [31:0] cpu_mem_wdata;
  logic [31:0] cpu_mem_wstrb;

  // Framebuffer address
  localparam integer FB_WORD_BASE = 'hC00;

  logic cpu_mem_ready;
  logic [31:0] cpu_mem_rdata;
  logic [31:0] mmio_addr;
  logic [31:0] mmio_rdata;

  // MMIO writes (TODO)
  logic mmio_wen;
  logic [31:0] mmio_wdata;

  cpu #(
    .INIT_FILE(`FPATH(prog.mem))
  ) my_cpu (
    .clk(clk_100mhz_buffered),
    .rst(sys_rst),

    // Flashing interface
    .flash_active(flash_active),
    .flash_addr(flash_addr),
    .flash_data(flash_data),
    .flash_wen(flash_wen),

    // Frame-buffer reading
    .clk_mmio(clk_pixel),
    .mmio_addr(mmio_addr),
    .mmio_rdata(mmio_rdata),
    .mmio_wen(mmio_wen),
    .mmio_wdata(mmio_wdata),
    .trap(led[15]),

    .cpu_mem_valid(cpu_mem_valid),
    .cpu_mem_instr(cpu_mem_instr),
    .cpu_mem_addr(cpu_mem_addr),
    .cpu_mem_wdata(cpu_mem_wdata),
    .cpu_mem_wstrb(cpu_mem_wstrb),
    .cpu_mem_ready(cpu_mem_ready),
    .cpu_mem_rdata(cpu_mem_rdata)
  );
  // ====================
 
  logic clk_pixel, clk_5x; // clock lines
  logic locked; // locked signal (we'll leave unused but still hook it up)
 
  // clock manager...creates 74.25 Hz and 5 times 74.25 MHz for pixel and TMDS
  hdmi_clk_wiz_720p mhdmicw (
    .reset(0),
    .locked(locked),
    .clk_ref(clk_100mhz_buffered),
    .clk_pixel(clk_pixel),
    .clk_tmds(clk_5x)
  );
 
  logic [10:0] h_count; // h_count of system!
  logic [9:0] v_count; // v_count of system!

  logic h_sync; // horizontal sync signal
  logic v_sync; // vertical sync signal
  logic active_draw; // ative draw! 1 when in drawing region.0 in blanking/sync
  logic new_frame; // one cycle active indicator of new frame of info!
  logic [5:0] frame_count; // 0 to 59 then rollover frame counter
 
  // written by you previously! (make sure you include in your hdl)
  // default instantiation so making signals for 720p
  video_sig_gen mvg(
    .pixel_clk(clk_pixel),
    .rst(sys_rst),
    .h_count(h_count),
    .v_count(v_count),
    .v_sync(v_sync),
    .h_sync(h_sync),
    .active_draw(active_draw),
    .new_frame(new_frame),
    .frame_count(frame_count)
  );
 
  logic [7:0] red, green, blue; // red green and blue pixel values for output
 
  // Get color using mmio_addr and mmio_rdata
  logic [7:0] fb_pixel;
  logic [31:0] pixel_offset;
  logic [31:0] pixel_offset_piped;

  always_comb begin
    // Read framebuffer for display
    pixel_offset = ((v_count >> 2) * 320 + (h_count >> 2));
    mmio_addr = (pixel_offset + FB_WORD_BASE) >> 2;
  end

  // Pipeline pixel offset by 2 cycles to match BRAM 2-cycle read latency
  pipeline #(.WIDTH(32), .DEPTH(2)) pixel_offset_pipeline (
    .clk(clk_pixel),
    .in(pixel_offset),
    .out(pixel_offset_piped)
  );

  // Extract byte using pipelined offset
  always_comb begin
    case (pixel_offset_piped & 2'b11)
      2'b00: fb_pixel = mmio_rdata[7:0];
      2'b01: fb_pixel = mmio_rdata[15:8];
      2'b10: fb_pixel = mmio_rdata[23:16];
      2'b11: fb_pixel = mmio_rdata[31:24];
    endcase
  end

  // ============ UART ==================
  // Prevent metastability
  logic uart_rx_buf0, uart_rx_buf1;
  always_ff @(posedge clk_100mhz_buffered) begin
    uart_rx_buf0 <= uart_rxd;
    uart_rx_buf1 <= uart_rx_buf0;
  end

  logic uart_rx_valid;
  logic [7:0] uart_rx_byte;

  uart_receive #(100_000_000, 115_200) uart_receiver (
    .clk(clk_100mhz_buffered),
    .rst(sys_rst),
    .din(uart_rx_buf1),
    .dout_valid(uart_rx_valid),
    .dout(uart_rx_byte)
  );

  assign led[7:0] = uart_rx_byte;
  // ==================================


  // ==== SEVEN SEGMENT DISPLAY =======
  seven_segment_controller(
    .clk(clk_100mhz_buffered),
    .rst(sys_rst),
    .val(flash_active ? flash_addr : cpu_mem_rdata),
    .cat(ss0_c),
    .an({ ss0_an, ss1_an })
  );
  assign ss1_c = ss0_c;
  // ==================================


  // ========= UART PROGRAMMER ========
  logic flash_active;
  logic [31:0] flash_addr;
  logic [31:0] flash_data;
  logic flash_wen;
  
  uart_memflash(
    .clk(clk_100mhz_buffered),
    .rst(sys_rst),
    .uart_rx_valid(uart_rx_valid),
    .uart_rx_byte(uart_rx_byte),
    .flash_active(flash_active),
    .flash_addr(flash_addr),
    .flash_data(flash_data),
    .flash_wen(flash_wen)
  );
  assign led[14] = flash_active;
  assign led[13] = uart_rx_valid;
  // ==================================


  // Extrapolate colors
  assign red = {fb_pixel[7:6], 5'b0};
  assign green = {fb_pixel[5:3], 4'b0};
  assign blue = {fb_pixel[2:0], 4'b0};
 
  logic [9:0] tmds_10b [0:2]; // output of each TMDS encoder!
  logic tmds_signal [2:0]; // output of each TMDS serializer!
 
  // three tmds_encoders (blue, green, red)
  // MISSING two more tmds encoders (one for green and one for blue)
  // note green should have no control signal like red
  // the blue channel DOES carry the two sync signals:
  //   * control[0] = horizontal sync signal
  //   * control[1] = vertical sync signal
  tmds_encoder tmds_blue(
    .clk(clk_pixel),
    .rst(sys_rst),
    .video_data(blue),
    .control({ v_sync, h_sync }),  //  control signals
    .video_enable(active_draw),
    .tmds(tmds_10b[0])
  );

  tmds_encoder tmds_green(
    .clk(clk_pixel),
    .rst(sys_rst),
    .video_data(green),
    .control(2'b0),
    .video_enable(active_draw),
    .tmds(tmds_10b[1]));
 
  tmds_encoder tmds_red(
    .clk(clk_pixel),
    .rst(sys_rst),
    .video_data(red),
    .control(2'b0),
    .video_enable(active_draw),
    .tmds(tmds_10b[2]));
 
  // three tmds_serializers (blue, green, red):
  tmds_serializer blue_ser(
    .clk_pixel(clk_pixel),
    .clk_5x(clk_5x),
    .rst(sys_rst),
    .tmds_in(tmds_10b[0]),
    .tmds_out(tmds_signal[0]));

  tmds_serializer green_ser(
    .clk_pixel(clk_pixel),
    .clk_5x(clk_5x),
    .rst(sys_rst),
    .tmds_in(tmds_10b[1]),
    .tmds_out(tmds_signal[1]));

  tmds_serializer red_ser(
    .clk_pixel(clk_pixel),
    .clk_5x(clk_5x),
    .rst(sys_rst),
    .tmds_in(tmds_10b[2]),
    .tmds_out(tmds_signal[2]));
 
  // output buffers generating differential signals:
  // three for the r,g,b signals and one that is at the pixel clock rate
  // the HDMI receivers use recover logic coupled with the control signals asserted
  // during blanking and sync periods to synchronize their faster bit clocks off
  // of the slower pixel clock (so they can recover a clock of about 742.5 MHz from
  // the slower 74.25 MHz clock)
  OBUFDS OBUFDS_blue (.I(tmds_signal[0]), .O(hdmi_tx_p[0]), .OB(hdmi_tx_n[0]));
  OBUFDS OBUFDS_green(.I(tmds_signal[1]), .O(hdmi_tx_p[1]), .OB(hdmi_tx_n[1]));
  OBUFDS OBUFDS_red  (.I(tmds_signal[2]), .O(hdmi_tx_p[2]), .OB(hdmi_tx_n[2]));
  OBUFDS OBUFDS_clock(.I(clk_pixel), .O(hdmi_clk_p), .OB(hdmi_clk_n));
 
endmodule //  top_level
`default_nettype wire
