`default_nettype none

module fp_add_bench_core #(
  parameter integer DUT_VARIANT = 0
) (
  input wire sysclk_p,
  input wire sysclk_n,
  input wire [7:0] sw,
  input wire [4:0] btn,
  output logic [7:0] led,
  output logic [2:0] hdmi_tx_p,
  output logic [2:0] hdmi_tx_n,
  output logic hdmi_clk_p,
  output logic hdmi_clk_n
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
  assign rst = btn[0] | ~sysclk_locked;

  logic [47:0] lfsr;
  fp a_reg;
  fp b_reg;
  logic is_sub_reg;
  fp sum;
  logic [31:0] checksum;

  generate
    if (DUT_VARIANT == 1) begin : gen_baseline
      fp_add_one_cycle_baseline dut (
        .clk(clk_100mhz),
        .rst(rst),
        .a(a_reg),
        .b(b_reg),
        .is_sub(is_sub_reg),
        .sum(sum)
      );
    end else if (DUT_VARIANT == 2) begin : gen_opt
      fp_add_one_cycle_opt dut (
        .clk(clk_100mhz),
        .rst(rst),
        .a(a_reg),
        .b(b_reg),
        .is_sub(is_sub_reg),
        .sum(sum)
      );
    end else begin : gen_production
      fp_add dut (
        .clk(clk_100mhz),
        .rst(rst),
        .a(a_reg),
        .b(b_reg),
        .is_sub(is_sub_reg),
        .sum(sum)
      );
    end
  endgenerate

  always_ff @(posedge clk_100mhz) begin
    if (rst) begin
      lfsr <= 48'h1;
      a_reg <= FP_ONE;
      b_reg <= FP_HALF_SCREEN_WIDTH;
      is_sub_reg <= 1'b0;
      checksum <= 32'h1;
    end else begin
      lfsr <= {lfsr[46:0], lfsr[47] ^ lfsr[42] ^ lfsr[38] ^ lfsr[37]};
      a_reg <= {lfsr[0] ^ sw[0], (lfsr[7:1] | 7'd1), lfsr[23:8]};
      b_reg <= {lfsr[24] ^ sw[1], (lfsr[31:25] | 7'd1), lfsr[47:32]};
      is_sub_reg <= lfsr[5] ^ sw[2];
      checksum <= {checksum[30:0], checksum[31] ^ sum.sign ^ is_sub_reg} ^ {8'h0, sum};
    end
  end

  always_comb begin
    led = checksum[7:0] ^ {7'b0, sysclk_locked};
    hdmi_tx_p = 3'b000;
    hdmi_tx_n = 3'b000;
    hdmi_clk_p = 1'b0;
    hdmi_clk_n = 1'b0;
  end
endmodule

module top_level (
  input wire sysclk_p,
  input wire sysclk_n,
  input wire [7:0] sw,
  input wire [4:0] btn,
  output logic [7:0] led,
  output logic [2:0] hdmi_tx_p,
  output logic [2:0] hdmi_tx_n,
  output logic hdmi_clk_p,
  output logic hdmi_clk_n
);
  fp_add_bench_core #(.DUT_VARIANT(0)) bench (
    .sysclk_p(sysclk_p),
    .sysclk_n(sysclk_n),
    .sw(sw),
    .btn(btn),
    .led(led),
    .hdmi_tx_p(hdmi_tx_p),
    .hdmi_tx_n(hdmi_tx_n),
    .hdmi_clk_p(hdmi_clk_p),
    .hdmi_clk_n(hdmi_clk_n)
  );
endmodule

module top_level_one_cycle_baseline (
  input wire sysclk_p,
  input wire sysclk_n,
  input wire [7:0] sw,
  input wire [4:0] btn,
  output logic [7:0] led,
  output logic [2:0] hdmi_tx_p,
  output logic [2:0] hdmi_tx_n,
  output logic hdmi_clk_p,
  output logic hdmi_clk_n
);
  fp_add_bench_core #(.DUT_VARIANT(1)) bench (
    .sysclk_p(sysclk_p),
    .sysclk_n(sysclk_n),
    .sw(sw),
    .btn(btn),
    .led(led),
    .hdmi_tx_p(hdmi_tx_p),
    .hdmi_tx_n(hdmi_tx_n),
    .hdmi_clk_p(hdmi_clk_p),
    .hdmi_clk_n(hdmi_clk_n)
  );
endmodule

module top_level_one_cycle_opt (
  input wire sysclk_p,
  input wire sysclk_n,
  input wire [7:0] sw,
  input wire [4:0] btn,
  output logic [7:0] led,
  output logic [2:0] hdmi_tx_p,
  output logic [2:0] hdmi_tx_n,
  output logic hdmi_clk_p,
  output logic hdmi_clk_n
);
  fp_add_bench_core #(.DUT_VARIANT(2)) bench (
    .sysclk_p(sysclk_p),
    .sysclk_n(sysclk_n),
    .sw(sw),
    .btn(btn),
    .led(led),
    .hdmi_tx_p(hdmi_tx_p),
    .hdmi_tx_n(hdmi_tx_n),
    .hdmi_clk_p(hdmi_clk_p),
    .hdmi_clk_n(hdmi_clk_n)
  );
endmodule

`default_nettype wire
