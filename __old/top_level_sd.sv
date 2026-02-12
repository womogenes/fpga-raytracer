`default_nettype none //  prevents system from inferring an undeclared logic (good practice)

`ifdef SYNTHESIS
  `define FPATH(X) `"X`"
`else /* ! SYNTHESIS */
  `define FPATH(X) `"../data/X`"
`endif  /* ! SYNTHESIS */
 
module top_level (
  input wire clk_100mhz, // crystal reference clock
  input wire [15:0] sw, // all 16 input slide switches
  input wire [3:0] btn, // all four momentary button switches
  output logic [15:0] led, // 16 green output LEDs (located right above switches)
  output logic [2:0] rgb0, // rgb led
  output logic [2:0] rgb1, // rgb led

  input wire sd_cipo,
  output logic sd_cs,
  output logic sd_copi,
  output logic sd_dclk,

  output logic [3:0] ss0_an,
  output logic [6:0] ss0_c,

  output logic [7:0] pmoda
);

  // shut up those rgb LEDs (active high):
  assign rgb1 = 0;
  assign rgb0 = 0;

  // have btn[0] control system reset
  logic sys_rst;
  assign sys_rst = btn[0]; // reset is btn[0]

  logic sd_trigger;
  logic [22:0] sd_block_addr;
  logic sd_ready;

  logic [7:0] sd_out;
  logic sd_valid;

  sd_reader test_reader (
    .clk(clk_100mhz),
    .rst(sys_rst),

    .trigger(sd_trigger),
    .block_addr(sd_block_addr),
    .ready(sd_ready),

    .byte_out(sd_out),
    .byte_valid(sd_valid),

    .copi(sd_copi),
    .cipo(sd_cipo),
    .dclk(sd_dclk),
    .cs(sd_cs)
  );

  logic [8:0] output_index;
  logic [8:0] read_index;
  logic [7:0] sd_output [511:0];
  logic finished_read;

  assign pmoda[0] = sd_cs;
  assign pmoda[1] = sd_dclk;
  assign pmoda[2] = sd_copi;
  assign pmoda[3] = sd_cipo;
  assign pmoda[4] = sys_rst;
  assign pmoda[5] = test_reader.state == test_reader.BOOT;

  always_ff @(posedge clk_100mhz) begin
    if (sys_rst) begin
      finished_read <= 0;
    end else if (sd_ready && ~finished_read) begin
      output_index <= 0;
      sd_block_addr <= 0;
      sd_trigger <= 1;
      finished_read <= 1;
    end else if (sd_valid) begin
      sd_output[output_index] <= sd_out;
      output_index <= output_index + 1;
    end
    
  end

  assign read_index = sw[8:0];
  assign led = sw;

  seven_segment_controller mem_display (
    .clk(clk_100mhz),
    .rst(sys_rst),
    .val({24'b0, sd_output[read_index]}),
    .cat(ss0_c),
    .an({4'b0, ss0_an})
  );


 
endmodule //  top_level
`default_nettype wire
