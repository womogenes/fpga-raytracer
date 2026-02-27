`timescale 1ns / 1ps
`default_nettype none

module prng_sphere_lfsr_fast (
  input wire clk,
  input wire rst,
  input wire [47:0] seed,
  output fp_vec3 rng_vec
);
  logic [47:0] lfsr_reg;
  logic feedback_bit;

  `ifdef SYNTHESIS
    logic ring_osc_bit;
    ring_osc_sampler ro_sampler(.clk(clk), .rst(rst), .rng_bit(ring_osc_bit));
    assign feedback_bit = lfsr_reg[47] ^ ring_osc_bit;
  `else
    assign feedback_bit = lfsr_reg[47];
  `endif

  always_ff @(posedge clk) begin
    if (rst)
      lfsr_reg <= seed;
    else begin
      lfsr_reg[0]     <= feedback_bit;
      lfsr_reg[1]     <= lfsr_reg[0]  ^ feedback_bit;
      lfsr_reg[26]    <= lfsr_reg[25] ^ feedback_bit;
      lfsr_reg[27]    <= lfsr_reg[26] ^ feedback_bit;
      lfsr_reg[25:2]  <= lfsr_reg[24:1];
      lfsr_reg[47:28] <= lfsr_reg[46:27];
    end
  end

  logic [2:0][15:0] rand_ints;
  fp [2:0] rand_fps;

  assign rand_ints = lfsr_reg;

  generate
    genvar i;
    for (i = 0; i < 3; i = i + 1) begin
      make_fp #(.WIDTH(16), .FRAC(-15)) converter (
        .clk(clk),
        .rst(rst),
        .n(rand_ints[i]),
        .x(rand_fps[i])
      );
    end
  endgenerate

  assign rng_vec = rand_fps;
endmodule

`default_nettype wire
