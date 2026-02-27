`default_nettype none

parameter integer RAY_RFLX_FAST_DELAY = FAST_VEC3_NORM_DELAY + VEC3_ADD_DELAY + 1;
parameter integer RAY_RFLX_BLEND_DELAY = RAY_RFLX_FAST_DELAY + VEC3_LERP_DELAY + FAST_VEC3_NORM_DELAY;

module ray_reflector (
  input wire clk,
  input wire rst,

  input fp_vec3 ray_dir,
  input fp_color ray_color,
  input fp_color income_light,

  input fp_vec3 hit_pos,
  input fp_vec3 hit_normal,
  input wire [7:0] hit_mat_idx,
  input wire hit_valid,

  output fp_vec3 new_dir,
  output fp_vec3 new_origin,
  output fp_color new_color,
  output fp_color new_income_light,
  output logic reflect_done,

  output logic [7:0] mat_dict_idx,
  input material mat_dict_mat,

  input wire [95:0] lfsr_seed
);
  localparam integer MAT_READ_DELAY = 2;
  localparam integer SPECULAR_REFLECT_DELAY = 8;
  localparam integer FAST_POST_MAT_DELAY = RAY_RFLX_FAST_DELAY - MAT_READ_DELAY;
  localparam integer BLEND_POST_MAT_DELAY = RAY_RFLX_BLEND_DELAY - MAT_READ_DELAY;
  localparam integer FAST_MAT_USE_DELAY = MAT_READ_DELAY + 1;
  localparam integer FAST_PATH_ALIGN_DELAY = RAY_RFLX_FAST_DELAY - (VEC3_SCALE_DELAY + VEC3_ADD_DELAY);
  localparam integer FAST_COLOR_ALIGN_DELAY = RAY_RFLX_FAST_DELAY - (FAST_MAT_USE_DELAY + VEC3_MUL_DELAY);
  localparam integer FAST_INCOME_ALIGN_DELAY = RAY_RFLX_FAST_DELAY - (FAST_MAT_USE_DELAY + VEC3_MUL_DELAY + VEC3_ADD_DELAY);
  localparam integer BLEND_DIR_ALIGN_DELAY = RAY_RFLX_FAST_DELAY - FAST_MAT_USE_DELAY;
  localparam integer SPECULAR_ALIGN_DELAY = RAY_RFLX_FAST_DELAY - SPECULAR_REFLECT_DELAY;
  localparam integer BLEND_ORIGIN_POS_DELAY = RAY_RFLX_BLEND_DELAY - VEC3_ADD_DELAY;
  localparam integer BLEND_ORIGIN_NORMAL_DELAY = RAY_RFLX_BLEND_DELAY - (VEC3_SCALE_DELAY + VEC3_ADD_DELAY);
  localparam integer BLEND_INCOME_ALIGN_DELAY = RAY_RFLX_BLEND_DELAY - (MAT_READ_DELAY + FP_MUL_DELAY + FP_ADD_DELAY);
  localparam integer BLEND_COLOR_ALIGN_DELAY = RAY_RFLX_BLEND_DELAY - (MAT_READ_DELAY + 2 + VEC3_LERP_DELAY + VEC3_MUL_DELAY);
  localparam integer FIFO_DEPTH = 32;
  localparam integer FIFO_ADDR_BITS = $clog2(FIFO_DEPTH);
  localparam fp EPSILON = 24'h370000;

  typedef struct packed {
    fp_vec3 dir;
    fp_vec3 origin;
    fp_color color;
    fp_color income;
  } reflect_payload_t;

  material hit_mat;
  logic mat_ready;
  logic reflect_done_fast;
  logic reflect_done_blend;

  fp spec_amt;
  fp one_sub_spec_amt;
  logic pure_diffuse;
  logic pure_specular;
  logic fast_path_now;
  logic [7:0] rng_specular;

  fp spec_amt_piped_dir;
  fp one_sub_spec_amt_piped_dir;
  fp spec_amt_piped_color;
  fp one_sub_spec_amt_piped_color;
  logic pure_specular_piped_fast;

  fp_vec3 rng_vec;
  fp_vec3 rng_added;
  fp_vec3 diffuse_dir;
  fp_vec3 specular_dir;
  fp_vec3 specular_dir_piped;
  fp_vec3 new_ray_dir_prenorm;
  fp_vec3 new_dir_blend;
  fp_vec3 new_dir_fast;

  fp_vec3 hit_pos_piped;
  fp_vec3 hit_normal_piped;
  fp_vec3 scaled_normal;
  fp_vec3 new_origin_blend;
  fp_vec3 hit_pos_fast_piped;
  fp_vec3 scaled_normal_fast;
  fp_vec3 new_origin_fast_unaligned;
  fp_vec3 new_origin_fast;

  fp_color ray_color_piped2;
  fp_color income_light_piped2;
  fp_color extra_income_light;
  fp_color new_income_light_unpiped;
  fp_color new_income_light_blend;
  fp_color ray_color_fast_piped2;
  fp_color income_light_fast_piped3;
  fp_color extra_income_light_fast;
  fp_color new_income_light_fast_unaligned;
  fp_color new_income_light_fast;

  fp_color mat_color_piped;
  fp_color mat_spec_color_piped;
  fp_color emit_color_fast_piped;
  fp_color mat_color_fast_piped;
  fp_color mat_spec_color_fast_piped;
  fp_color true_mat_color;
  fp_color ray_color_piped7;
  fp_color new_color_unpiped;
  fp_color new_color_blend;
  fp_color new_color_diffuse_unaligned;
  fp_color new_color_specular_unaligned;
  fp_color new_color_fast_unaligned;
  fp_color new_color_fast;

  reflect_payload_t fast_payload_now;
  reflect_payload_t blend_payload_now;
  reflect_payload_t fast_fifo [0:FIFO_DEPTH-1];
  reflect_payload_t blend_fifo [0:FIFO_DEPTH-1];
  logic order_fifo [0:FIFO_DEPTH-1];
  logic [FIFO_ADDR_BITS-1:0] fast_wr_ptr;
  logic [FIFO_ADDR_BITS-1:0] fast_rd_ptr;
  logic [FIFO_ADDR_BITS-1:0] blend_wr_ptr;
  logic [FIFO_ADDR_BITS-1:0] blend_rd_ptr;
  logic [FIFO_ADDR_BITS-1:0] order_wr_ptr;
  logic [FIFO_ADDR_BITS-1:0] order_rd_ptr;
  logic [FIFO_ADDR_BITS:0] fast_count;
  logic [FIFO_ADDR_BITS:0] blend_count;
  logic [FIFO_ADDR_BITS:0] order_count;
  reflect_payload_t fast_fifo_head;
  reflect_payload_t blend_fifo_head;
  logic order_head_is_fast;
  logic fast_bypass;
  logic blend_bypass;
  logic fast_pop;
  logic blend_pop;
  logic fast_push;
  logic blend_push;
  logic order_push;
  logic order_pop;
  reflect_payload_t out_payload;

  assign mat_dict_idx = hit_mat_idx;
  assign hit_mat = mat_dict_mat;
  assign fast_fifo_head = fast_fifo[fast_rd_ptr];
  assign blend_fifo_head = blend_fifo[blend_rd_ptr];
  assign order_head_is_fast = order_fifo[order_rd_ptr];

  pipeline #(.WIDTH(1), .DEPTH(MAT_READ_DELAY)) launch_pipe (
    .clk(clk),
    .in(hit_valid),
    .out(mat_ready)
  );

  prng8 rng8 (
    .clk(clk),
    .rst(rst),
    .seed(lfsr_seed[47:0]),
    .rng(rng_specular)
  );

  always_comb begin
    if (rng_specular <= hit_mat.specular_prob) begin
      spec_amt = hit_mat.smoothness;
      one_sub_spec_amt = hit_mat.one_sub_smoothness;
    end else begin
      spec_amt = FP_ZER0;
      one_sub_spec_amt = FP_ONE;
    end
  end

  assign pure_diffuse = (spec_amt == FP_ZER0);
  assign pure_specular = (spec_amt == FP_ONE);
  assign fast_path_now = pure_diffuse || pure_specular;

  pipeline #(.WIDTH(FP_BITS), .DEPTH(BLEND_DIR_ALIGN_DELAY)) spec_amt_dir_pipe (
    .clk(clk),
    .in(spec_amt),
    .out(spec_amt_piped_dir)
  );
  pipeline #(.WIDTH(FP_BITS), .DEPTH(BLEND_DIR_ALIGN_DELAY)) one_sub_spec_amt_dir_pipe (
    .clk(clk),
    .in(one_sub_spec_amt),
    .out(one_sub_spec_amt_piped_dir)
  );
  pipeline #(.WIDTH(FP_BITS), .DEPTH(2)) spec_amt_color_pipe (
    .clk(clk),
    .in(spec_amt),
    .out(spec_amt_piped_color)
  );
  pipeline #(.WIDTH(FP_BITS), .DEPTH(2)) one_sub_spec_amt_color_pipe (
    .clk(clk),
    .in(one_sub_spec_amt),
    .out(one_sub_spec_amt_piped_color)
  );
  pipeline #(.WIDTH(1), .DEPTH(FAST_POST_MAT_DELAY)) pure_spec_fast_pipe (
    .clk(clk),
    .in(pure_specular),
    .out(pure_specular_piped_fast)
  );

  prng_sphere_lfsr_fast prng_sphere (
    .clk(clk),
    .rst(rst),
    .seed(lfsr_seed[95:48]),
    .rng_vec(rng_vec)
  );
  fp_vec3_add diffuse_adder (
    .clk(clk),
    .rst(rst),
    .v(rng_vec),
    .w(hit_normal),
    .is_sub(1'b0),
    .sum(rng_added)
  );
  fp_vec3_normalize_fast diffuse_normalizer (
    .clk(clk),
    .rst(rst),
    .v(rng_added),
    .normed(diffuse_dir)
  );

  specular_reflect spec_reflector (
    .clk(clk),
    .rst(rst),
    .in_dir(ray_dir),
    .normal(hit_normal),
    .out_dir(specular_dir)
  );
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(SPECULAR_ALIGN_DELAY)) spec_dir_pipe (
    .clk(clk),
    .in(specular_dir),
    .out(specular_dir_piped)
  );

  fp_vec3_lerp lerp_dir (
    .clk(clk),
    .rst(rst),
    .v(diffuse_dir),
    .w(specular_dir_piped),
    .t(spec_amt_piped_dir),
    .one_sub_t(one_sub_spec_amt_piped_dir),
    .lerped(new_ray_dir_prenorm)
  );
  fp_vec3_normalize_fast norm_dir (
    .clk(clk),
    .rst(rst),
    .v(new_ray_dir_prenorm),
    .normed(new_dir_blend)
  );
  assign new_dir_fast = pure_specular_piped_fast ? specular_dir_piped : diffuse_dir;

  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(BLEND_ORIGIN_POS_DELAY)) origin_pipe (
    .clk(clk),
    .in(hit_pos),
    .out(hit_pos_piped)
  );
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(BLEND_ORIGIN_NORMAL_DELAY)) normal_pipe (
    .clk(clk),
    .in(hit_normal),
    .out(hit_normal_piped)
  );
  fp_vec3_scale offset_scale (
    .clk(clk),
    .rst(rst),
    .v(hit_normal_piped),
    .s(EPSILON),
    .scaled(scaled_normal)
  );
  fp_vec3_add offset_add (
    .clk(clk),
    .rst(rst),
    .v(hit_pos_piped),
    .w(scaled_normal),
    .sum(new_origin_blend)
  );

  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(VEC3_SCALE_DELAY)) hit_pos_fast_pipe (
    .clk(clk),
    .in(hit_pos),
    .out(hit_pos_fast_piped)
  );
  fp_vec3_scale offset_scale_fast (
    .clk(clk),
    .rst(rst),
    .v(hit_normal),
    .s(EPSILON),
    .scaled(scaled_normal_fast)
  );
  fp_vec3_add offset_add_fast (
    .clk(clk),
    .rst(rst),
    .v(hit_pos_fast_piped),
    .w(scaled_normal_fast),
    .sum(new_origin_fast_unaligned)
  );
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(FAST_PATH_ALIGN_DELAY)) new_origin_fast_pipe (
    .clk(clk),
    .in(new_origin_fast_unaligned),
    .out(new_origin_fast)
  );

  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(MAT_READ_DELAY)) ray_color_income_pipe (
    .clk(clk),
    .in(ray_color),
    .out(ray_color_piped2)
  );
  fp_vec3_mul mul_extra_income_light (
    .clk(clk),
    .rst(rst),
    .v(ray_color_piped2),
    .w(hit_mat.emit_color),
    .prod(extra_income_light)
  );
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(MAT_READ_DELAY)) income_light_pipe (
    .clk(clk),
    .in(income_light),
    .out(income_light_piped2)
  );
  fp_vec3_add add_new_income_light (
    .clk(clk),
    .rst(rst),
    .v(extra_income_light),
    .w(income_light_piped2),
    .is_sub(1'b0),
    .sum(new_income_light_unpiped)
  );
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(BLEND_INCOME_ALIGN_DELAY)) new_income_light_pipe (
    .clk(clk),
    .in(new_income_light_unpiped),
    .out(new_income_light_blend)
  );

  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(FAST_MAT_USE_DELAY)) ray_color_fast_pipe (
    .clk(clk),
    .in(ray_color),
    .out(ray_color_fast_piped2)
  );
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(FAST_MAT_USE_DELAY)) emit_color_fast_pipe (
    .clk(clk),
    .in(hit_mat.emit_color),
    .out(emit_color_fast_piped)
  );
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(FAST_MAT_USE_DELAY)) mat_color_fast_pipe (
    .clk(clk),
    .in(hit_mat.color),
    .out(mat_color_fast_piped)
  );
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(FAST_MAT_USE_DELAY)) mat_spec_color_fast_pipe (
    .clk(clk),
    .in(hit_mat.spec_color),
    .out(mat_spec_color_fast_piped)
  );
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(FAST_MAT_USE_DELAY + VEC3_MUL_DELAY)) income_light_fast_pipe (
    .clk(clk),
    .in(income_light),
    .out(income_light_fast_piped3)
  );
  fp_vec3_mul mul_extra_income_light_fast (
    .clk(clk),
    .rst(rst),
    .v(ray_color_fast_piped2),
    .w(emit_color_fast_piped),
    .prod(extra_income_light_fast)
  );
  fp_vec3_add add_new_income_light_fast (
    .clk(clk),
    .rst(rst),
    .v(extra_income_light_fast),
    .w(income_light_fast_piped3),
    .is_sub(1'b0),
    .sum(new_income_light_fast_unaligned)
  );
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(FAST_INCOME_ALIGN_DELAY)) new_income_light_fast_pipe (
    .clk(clk),
    .in(new_income_light_fast_unaligned),
    .out(new_income_light_fast)
  );

  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(2)) mat_color_pipe (
    .clk(clk),
    .in(hit_mat.color),
    .out(mat_color_piped)
  );
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(2)) mat_spec_color_pipe (
    .clk(clk),
    .in(hit_mat.spec_color),
    .out(mat_spec_color_piped)
  );
  fp_vec3_lerp lerp_true_mat_color (
    .clk(clk),
    .rst(rst),
    .v(mat_color_piped),
    .w(mat_spec_color_piped),
    .t(spec_amt_piped_color),
    .one_sub_t(one_sub_spec_amt_piped_color),
    .lerped(true_mat_color)
  );
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(7)) ray_color_pipe (
    .clk(clk),
    .in(ray_color),
    .out(ray_color_piped7)
  );
  fp_vec3_mul mul_new_ray_color (
    .clk(clk),
    .rst(rst),
    .v(ray_color_piped7),
    .w(true_mat_color),
    .prod(new_color_unpiped)
  );
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(BLEND_COLOR_ALIGN_DELAY)) new_ray_color_pipe (
    .clk(clk),
    .in(new_color_unpiped),
    .out(new_color_blend)
  );

  fp_vec3_mul mul_new_ray_color_diffuse (
    .clk(clk),
    .rst(rst),
    .v(ray_color_fast_piped2),
    .w(mat_color_fast_piped),
    .prod(new_color_diffuse_unaligned)
  );
  fp_vec3_mul mul_new_ray_color_specular (
    .clk(clk),
    .rst(rst),
    .v(ray_color_fast_piped2),
    .w(mat_spec_color_fast_piped),
    .prod(new_color_specular_unaligned)
  );
  assign new_color_fast_unaligned = pure_specular_piped_fast ? new_color_specular_unaligned : new_color_diffuse_unaligned;
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(FAST_COLOR_ALIGN_DELAY)) new_color_fast_pipe (
    .clk(clk),
    .in(new_color_fast_unaligned),
    .out(new_color_fast)
  );

  pipeline #(.WIDTH(1), .DEPTH(FAST_POST_MAT_DELAY)) reflect_done_fast_pipe (
    .clk(clk),
    .in(mat_ready && fast_path_now),
    .out(reflect_done_fast)
  );
  pipeline #(.WIDTH(1), .DEPTH(BLEND_POST_MAT_DELAY)) reflect_done_blend_pipe (
    .clk(clk),
    .in(mat_ready && !fast_path_now),
    .out(reflect_done_blend)
  );

  assign fast_payload_now.dir = new_dir_fast;
  assign fast_payload_now.origin = new_origin_fast;
  assign fast_payload_now.color = new_color_fast;
  assign fast_payload_now.income = new_income_light_fast;
  assign blend_payload_now.dir = new_dir_blend;
  assign blend_payload_now.origin = new_origin_blend;
  assign blend_payload_now.color = new_color_blend;
  assign blend_payload_now.income = new_income_light_blend;

  assign order_push = mat_ready;
  assign fast_bypass = (order_count != 0) && order_head_is_fast && (fast_count == 0) && reflect_done_fast;
  assign blend_bypass = (order_count != 0) && !order_head_is_fast && (blend_count == 0) && reflect_done_blend;
  assign fast_pop = (order_count != 0) && order_head_is_fast && (fast_count != 0);
  assign blend_pop = (order_count != 0) && !order_head_is_fast && (blend_count != 0);
  assign order_pop = fast_bypass || blend_bypass || fast_pop || blend_pop;
  assign fast_push = reflect_done_fast && !fast_bypass;
  assign blend_push = reflect_done_blend && !blend_bypass;

  always_comb begin
    reflect_done = 1'b0;
    out_payload = '0;

    if (fast_bypass) begin
      reflect_done = 1'b1;
      out_payload = fast_payload_now;
    end else if (fast_pop) begin
      reflect_done = 1'b1;
      out_payload = fast_fifo_head;
    end else if (blend_bypass) begin
      reflect_done = 1'b1;
      out_payload = blend_payload_now;
    end else if (blend_pop) begin
      reflect_done = 1'b1;
      out_payload = blend_fifo_head;
    end
  end

  assign new_dir = out_payload.dir;
  assign new_origin = out_payload.origin;
  assign new_color = out_payload.color;
  assign new_income_light = out_payload.income;

  always_ff @(posedge clk) begin
    if (rst) begin
      fast_wr_ptr <= '0;
      fast_rd_ptr <= '0;
      blend_wr_ptr <= '0;
      blend_rd_ptr <= '0;
      order_wr_ptr <= '0;
      order_rd_ptr <= '0;
      fast_count <= '0;
      blend_count <= '0;
      order_count <= '0;
    end else begin
      if (order_push) begin
        order_fifo[order_wr_ptr] <= fast_path_now;
        order_wr_ptr <= order_wr_ptr + 1'b1;
      end
      if (order_pop) begin
        order_rd_ptr <= order_rd_ptr + 1'b1;
      end
      case ({order_push, order_pop})
        2'b10: order_count <= order_count + 1'b1;
        2'b01: order_count <= order_count - 1'b1;
        default: order_count <= order_count;
      endcase

      if (fast_push) begin
        fast_fifo[fast_wr_ptr] <= fast_payload_now;
        fast_wr_ptr <= fast_wr_ptr + 1'b1;
      end
      if (fast_pop) begin
        fast_rd_ptr <= fast_rd_ptr + 1'b1;
      end
      case ({fast_push, fast_pop})
        2'b10: fast_count <= fast_count + 1'b1;
        2'b01: fast_count <= fast_count - 1'b1;
        default: fast_count <= fast_count;
      endcase

      if (blend_push) begin
        blend_fifo[blend_wr_ptr] <= blend_payload_now;
        blend_wr_ptr <= blend_wr_ptr + 1'b1;
      end
      if (blend_pop) begin
        blend_rd_ptr <= blend_rd_ptr + 1'b1;
      end
      case ({blend_push, blend_pop})
        2'b10: blend_count <= blend_count + 1'b1;
        2'b01: blend_count <= blend_count - 1'b1;
        default: blend_count <= blend_count;
      endcase
    end
  end
endmodule

`default_nettype wire
