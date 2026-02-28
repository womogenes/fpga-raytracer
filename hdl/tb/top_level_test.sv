`default_nettype none

module top_level (
  input wire sysclk_p,
  input wire sysclk_n,
  input wire btn,
  output logic [7:0] led
);
  wire clk_100mhz;
  wire sysclk_locked;

  clkwiz sysclk_wiz (
    .sysclk_p(sysclk_p),
    .sysclk_n(sysclk_n),
    .clk_100mhz(clk_100mhz),
    .locked(sysclk_locked)
  );

  logic rst;
  assign rst = btn | ~sysclk_locked;

  logic [47:0] lfsr;
  fp a_reg;
  fp b_reg;
  logic is_sub_reg;
  fp sum;
  logic [31:0] checksum;

  fp_add dut (
    .clk(clk_100mhz),
    .rst(rst),
    .a(a_reg),
    .b(b_reg),
    .is_sub(is_sub_reg),
    .sum(sum)
  );

  always_ff @(posedge clk_100mhz) begin
    if (rst) begin
      lfsr <= 48'h1;
      a_reg <= FP_ONE;
      b_reg <= FP_HALF_SCREEN_WIDTH;
      is_sub_reg <= 1'b0;
      checksum <= 32'h1;
    end else begin
      lfsr <= {lfsr[46:0], lfsr[47] ^ lfsr[42] ^ lfsr[38] ^ lfsr[37]};
      a_reg <= {lfsr[0], (lfsr[7:1] | 7'd1), lfsr[23:8]};
      b_reg <= {lfsr[24], (lfsr[31:25] | 7'd1), lfsr[47:32]};
      is_sub_reg <= lfsr[5];
      checksum <= {checksum[30:0], checksum[31] ^ sum.sign ^ is_sub_reg} ^ {8'h0, sum};
    end
  end

  assign led = checksum[7:0] ^ {7'b0, sysclk_locked};
endmodule

`default_nettype wire
