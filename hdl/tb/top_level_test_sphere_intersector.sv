`default_nettype none

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
  localparam fp FP_ZERO = FP_ZER0;
  localparam fp FP_HALF = 'h3e0000;
  localparam fp FP_QUARTER = 'h3d0000;
  localparam fp FP_INV_SQRT2 = 'h3e6a0a;
  localparam fp FP_ONE_AND_HALF = 'h3f8000;
  localparam fp FP_FOUR = 'h410000;

  function automatic fp fp_negate(input fp value);
    begin
      fp_negate = {~value.sign, value.exp, value.mant};
    end
  endfunction

  function automatic fp_vec3 pack_vec3(input fp x, input fp y, input fp z);
    begin
      pack_vec3 = {x, y, z};
    end
  endfunction

  function automatic fp choose_signed_mag(input logic sign, input logic [1:0] mag_sel);
    fp mag;
    begin
      case (mag_sel)
        2'b00: mag = FP_ZERO;
        2'b01: mag = FP_HALF;
        2'b10: mag = FP_ONE;
        default: mag = FP_TWO;
      endcase
      choose_signed_mag = sign ? fp_negate(mag) : mag;
    end
  endfunction

  function automatic fp_vec3 choose_ray_dir(input logic [2:0] sel);
    begin
      case (sel)
        3'd0: choose_ray_dir = pack_vec3(FP_ZERO, FP_ONE, FP_ZERO);
        3'd1: choose_ray_dir = pack_vec3(FP_INV_SQRT2, FP_INV_SQRT2, FP_ZERO);
        3'd2: choose_ray_dir = pack_vec3(fp_negate(FP_INV_SQRT2), FP_INV_SQRT2, FP_ZERO);
        3'd3: choose_ray_dir = pack_vec3(FP_ZERO, FP_INV_SQRT2, FP_INV_SQRT2);
        3'd4: choose_ray_dir = pack_vec3(FP_ZERO, FP_INV_SQRT2, fp_negate(FP_INV_SQRT2));
        3'd5: choose_ray_dir = pack_vec3(FP_HALF, FP_INV_SQRT2, FP_HALF);
        3'd6: choose_ray_dir = pack_vec3(fp_negate(FP_HALF), FP_INV_SQRT2, FP_HALF);
        default: choose_ray_dir = pack_vec3(FP_HALF, FP_INV_SQRT2, fp_negate(FP_HALF));
      endcase
    end
  endfunction

  function automatic fp choose_center_y(input logic [1:0] sel);
    begin
      case (sel)
        2'd0: choose_center_y = FP_ONE_AND_HALF;
        2'd1: choose_center_y = FP_TWO;
        2'd2: choose_center_y = FP_THREE;
        default: choose_center_y = FP_FOUR;
      endcase
    end
  endfunction

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

  logic [63:0] lfsr;
  fp_vec3 ray_origin_reg;
  fp_vec3 ray_dir_reg;
  fp_vec3 sphere_center_reg;
  fp sphere_rad_sq_reg;
  fp sphere_rad_inv_reg;

  logic hit;
  fp_vec3 hit_pos;
  fp hit_dist;
  fp_vec3 hit_norm;
  logic [31:0] checksum;

  sphere_intersector dut (
    .clk(clk_100mhz),
    .rst(rst),
    .ray_origin(ray_origin_reg),
    .ray_dir(ray_dir_reg),
    .sphere_center(sphere_center_reg),
    .sphere_rad_sq(sphere_rad_sq_reg),
    .sphere_rad_inv(sphere_rad_inv_reg),
    .hit(hit),
    .hit_pos(hit_pos),
    .hit_dist(hit_dist),
    .hit_norm(hit_norm)
  );

  always_ff @(posedge clk_100mhz) begin
    if (rst) begin
      lfsr <= 64'h1;
      ray_origin_reg <= pack_vec3(FP_ZERO, FP_ZERO, FP_ZERO);
      ray_dir_reg <= pack_vec3(FP_ZERO, FP_ONE, FP_ZERO);
      sphere_center_reg <= pack_vec3(FP_ZERO, FP_TWO, FP_ZERO);
      sphere_rad_sq_reg <= FP_ONE;
      sphere_rad_inv_reg <= FP_ONE;
      checksum <= 32'h1;
    end else begin
      lfsr <= {
        lfsr[62:0],
        lfsr[63] ^ lfsr[62] ^ lfsr[60] ^ lfsr[59] ^ sw[0]
      };

      ray_origin_reg <= pack_vec3(
        choose_signed_mag(lfsr[0], lfsr[2:1]),
        choose_signed_mag(lfsr[3], 2'b00),
        choose_signed_mag(lfsr[4], lfsr[6:5])
      );
      ray_dir_reg <= choose_ray_dir(lfsr[9:7]);
      sphere_center_reg <= pack_vec3(
        choose_signed_mag(lfsr[10], lfsr[12:11]),
        choose_center_y(lfsr[14:13]),
        choose_signed_mag(lfsr[15], lfsr[17:16])
      );

      case (lfsr[19:18])
        2'b00: begin
          sphere_rad_sq_reg <= FP_QUARTER;
          sphere_rad_inv_reg <= FP_TWO;
        end
        2'b01: begin
          sphere_rad_sq_reg <= FP_ONE;
          sphere_rad_inv_reg <= FP_ONE;
        end
        default: begin
          sphere_rad_sq_reg <= FP_FOUR;
          sphere_rad_inv_reg <= FP_HALF;
        end
      endcase

      checksum <= {checksum[30:0], checksum[31] ^ hit ^ sw[1]} ^
        {hit_dist[15:0], hit_pos.x[7:0], hit_norm.y[7:0]};
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

`default_nettype wire
