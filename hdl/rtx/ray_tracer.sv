`default_nettype none

module ray_tracer #(
  parameter integer WIDTH = 1280,
  parameter integer HEIGHT = 720,
  parameter integer WORK_FIFO_DEPTH = 8,
  parameter integer BOUNCE_RESERVE_SLOTS = 1,
  parameter integer RESULT_FIFO_DEPTH = 8,
  parameter integer NUM_INTERSECTORS = 8
) (
  input wire clk,
  input wire rst,

  input wire [10:0] pixel_h_in,
  input wire [9:0] pixel_v_in,

  input fp_vec3 ray_origin,
  input fp_vec3 ray_dir,
  input wire ray_valid,
  output logic ray_ready,

  output logic ray_done,
  output fp_vec3 pixel_color,
  output logic [10:0] pixel_h_out,
  output logic [9:0] pixel_v_out,

  input wire [$clog2(MAX_NUM_OBJS)-1:0] num_objs,
  input object obj,

  output wire [7:0] mat_dict_idx,
  input material mat_dict_mat,

  input wire [7:0] max_bounces,
  input wire [95:0] lfsr_seed
);
  localparam integer RAY_CTX_BITS = 11 + 10 + (2 * FP_VEC3_BITS) + (2 * FP_VEC3_BITS) + 8;
  localparam integer RESULT_BITS = 11 + 10 + FP_VEC3_BITS;
  localparam integer REFLECT_META_BITS = 11 + 10 + 8;
  localparam integer REFLECT_DONE_DELAY = 37;
  localparam integer LANE_IDX_BITS = (NUM_INTERSECTORS <= 1) ? 1 : $clog2(NUM_INTERSECTORS);

  function automatic logic [$clog2(WORK_FIFO_DEPTH)-1:0] fifo_next_ptr(
    input logic [$clog2(WORK_FIFO_DEPTH)-1:0] ptr
  );
    if (ptr == WORK_FIFO_DEPTH - 1) begin
      fifo_next_ptr = '0;
    end else begin
      fifo_next_ptr = ptr + 1'b1;
    end
  endfunction

  function automatic logic [$clog2(RESULT_FIFO_DEPTH)-1:0] result_next_ptr(
    input logic [$clog2(RESULT_FIFO_DEPTH)-1:0] ptr
  );
    if (ptr == RESULT_FIFO_DEPTH - 1) begin
      result_next_ptr = '0;
    end else begin
      result_next_ptr = ptr + 1'b1;
    end
  endfunction

  logic [RAY_CTX_BITS-1:0] work_fifo_mem [WORK_FIFO_DEPTH-1:0];
  logic [$clog2(WORK_FIFO_DEPTH)-1:0] work_read_ptr;
  logic [$clog2(WORK_FIFO_DEPTH)-1:0] work_write_ptr;
  logic [$clog2(WORK_FIFO_DEPTH + 1)-1:0] work_count;
  logic [RAY_CTX_BITS-1:0] work_head_bits;

  logic work_empty;
  logic work_full;
  logic work_read;
  logic work_write;
  logic work_can_write;
  logic work_read_will_free_slot;
  logic primary_slot_open;
  logic [$clog2(WORK_FIFO_DEPTH + REFLECT_DONE_DELAY + 2)-1:0] reflect_inflight_count;
  logic [$clog2(WORK_FIFO_DEPTH + REFLECT_DONE_DELAY + 2)-1:0] reserved_bounce_slots;
  logic [$clog2(WORK_FIFO_DEPTH + REFLECT_DONE_DELAY + 2)-1:0] effective_work_count;

  logic [RAY_CTX_BITS-1:0] enqueue_ctx_bits;
  logic enqueue_from_pending_primary;
  logic enqueue_from_pending_bounce;
  logic enqueue_from_primary_now;
  logic enqueue_from_bounce_now;

  logic pending_primary_valid;
  logic [RAY_CTX_BITS-1:0] pending_primary_bits;
  logic pending_bounce_valid;
  logic [RAY_CTX_BITS-1:0] pending_bounce_bits;

  logic [RAY_CTX_BITS-1:0] primary_ctx_bits;
  logic [RAY_CTX_BITS-1:0] bounce_ctx_bits;
  logic primary_now_valid;
  logic bounce_now_valid;
  logic primary_capture_pending;
  logic bounce_capture_pending;

  logic [NUM_INTERSECTORS-1:0] intx_active;
  logic [NUM_INTERSECTORS-1:0] ray_valid_intx;
  logic [NUM_INTERSECTORS-1:0] ray_done_intx;
  logic [RAY_CTX_BITS-1:0] intx_ctx_bits [NUM_INTERSECTORS-1:0];
  logic [7:0] intx_hit_mat_idx [NUM_INTERSECTORS-1:0];
  fp_vec3 intx_hit_pos [NUM_INTERSECTORS-1:0];
  fp_vec3 intx_hit_norm [NUM_INTERSECTORS-1:0];
  logic [NUM_INTERSECTORS-1:0] intx_hit_any;

  logic intx_idle_found;
  logic [LANE_IDX_BITS-1:0] launch_lane_idx;
  logic [NUM_INTERSECTORS-1:0] intx_done_mask;
  logic intx_done_found;
  logic [LANE_IDX_BITS-1:0] done_lane_idx;
  logic [RAY_CTX_BITS-1:0] done_ctx_bits;
  logic [7:0] done_hit_mat_idx;
  fp_vec3 done_hit_pos;
  fp_vec3 done_hit_norm;
  logic done_hit_any;

  logic capture_reflector;
  logic launch_reflector;
  logic reflect_valid;
  logic [RAY_CTX_BITS-1:0] reflect_ctx_bits;
  logic [7:0] reflect_hit_mat_idx;
  fp_vec3 reflect_hit_pos;
  fp_vec3 reflect_hit_norm;
  logic [REFLECT_META_BITS-1:0] reflect_meta_in_bits;
  logic [REFLECT_META_BITS-1:0] reflect_meta_out_bits;

  fp_vec3 rflx_new_dir;
  fp_vec3 rflx_new_origin;
  fp_color rflx_new_color;
  fp_color rflx_new_income_light;
  logic ray_done_reflect;

  logic reflect_is_final;

  logic miss_result_now_valid;
  logic [RESULT_BITS-1:0] miss_result_now_bits;
  logic reflect_result_now_valid;
  logic [RESULT_BITS-1:0] reflect_result_now_bits;
  logic result_pop;
  logic result_empty;
  logic [RESULT_BITS-1:0] result_head_bits;
  logic [RESULT_BITS-1:0] result_fifo_mem [RESULT_FIFO_DEPTH-1:0];
  logic [$clog2(RESULT_FIFO_DEPTH)-1:0] result_read_ptr;
  logic [$clog2(RESULT_FIFO_DEPTH)-1:0] result_write_ptr;
  logic [$clog2(RESULT_FIFO_DEPTH + 1)-1:0] result_count;
  logic [1:0] result_push_count;
  logic [RESULT_BITS-1:0] result_push0_bits;
  logic [$clog2(RESULT_FIFO_DEPTH)-1:0] result_write_ptr_after_push0;

  logic [10:0] work_head_pixel_h;
  logic [9:0] work_head_pixel_v;
  fp_vec3 work_head_ray_origin;
  fp_vec3 work_head_ray_dir;
  fp_color work_head_income_light;
  fp_color work_head_ray_color;
  logic [7:0] work_head_bounce_count;

  logic [10:0] intx_ctx_pixel_h [NUM_INTERSECTORS-1:0];
  logic [9:0] intx_ctx_pixel_v [NUM_INTERSECTORS-1:0];
  fp_vec3 intx_ctx_ray_origin [NUM_INTERSECTORS-1:0];
  fp_vec3 intx_ctx_ray_dir [NUM_INTERSECTORS-1:0];
  fp_color intx_ctx_income_light [NUM_INTERSECTORS-1:0];
  fp_color intx_ctx_ray_color [NUM_INTERSECTORS-1:0];
  logic [7:0] intx_ctx_bounce_count [NUM_INTERSECTORS-1:0];

  logic [10:0] done_ctx_pixel_h;
  logic [9:0] done_ctx_pixel_v;
  fp_vec3 done_ctx_ray_dir;
  fp_color done_ctx_income_light;
  fp_color done_ctx_ray_color;
  logic [7:0] done_ctx_bounce_count;

  logic [10:0] reflect_meta_pixel_h;
  logic [9:0] reflect_meta_pixel_v;
  logic [7:0] reflect_meta_bounce_count;
  logic [10:0] reflect_ctx_pixel_h;
  logic [9:0] reflect_ctx_pixel_v;
  fp_vec3 reflect_ctx_ray_dir;
  fp_color reflect_ctx_income_light;
  fp_color reflect_ctx_ray_color;
  logic [7:0] reflect_ctx_bounce_count;

  genvar lane_idx;
  integer lane;

  assign work_head_bits = work_fifo_mem[work_read_ptr];
  assign {
    work_head_pixel_h,
    work_head_pixel_v,
    work_head_ray_origin,
    work_head_ray_dir,
    work_head_income_light,
    work_head_ray_color,
    work_head_bounce_count
  } = work_head_bits;

  assign {
    done_ctx_pixel_h,
    done_ctx_pixel_v,
    done_ctx_ray_dir,
    done_ctx_income_light,
    done_ctx_ray_color,
    done_ctx_bounce_count
  } = done_ctx_bits;

  assign {
    reflect_meta_pixel_h,
    reflect_meta_pixel_v,
    reflect_meta_bounce_count
  } = reflect_meta_out_bits;
  assign {
    reflect_ctx_pixel_h,
    reflect_ctx_pixel_v,
    reflect_ctx_ray_dir,
    reflect_ctx_income_light,
    reflect_ctx_ray_color,
    reflect_ctx_bounce_count
  } = reflect_ctx_bits;

  assign primary_ctx_bits = {
    pixel_h_in,
    pixel_v_in,
    ray_origin,
    ray_dir,
    {FP_ZER0, FP_ZER0, FP_ZER0},
    {FP_ONE, FP_ONE, FP_ONE},
    8'd0
  };
  assign primary_now_valid = ray_valid;

  assign reflect_is_final = (max_bounces <= 1) || (reflect_meta_bounce_count >= max_bounces - 1'b1);
  assign bounce_ctx_bits = {
    reflect_meta_pixel_h,
    reflect_meta_pixel_v,
    rflx_new_origin,
    rflx_new_dir,
    rflx_new_income_light,
    rflx_new_color,
    reflect_meta_bounce_count + 1'b1
  };
  assign bounce_now_valid = ray_done_reflect && !reflect_is_final;

  assign work_empty = (work_count == 0);
  assign work_full = (work_count == WORK_FIFO_DEPTH);
  assign work_read = intx_idle_found && !work_empty;
  assign work_read_will_free_slot = work_read && !work_empty;
  assign work_can_write = !work_full || work_read_will_free_slot;
  assign effective_work_count = work_read_will_free_slot ? (work_count - 1'b1) : work_count;
  assign reserved_bounce_slots =
    reflect_inflight_count +
    pending_bounce_valid +
    launch_reflector +
    capture_reflector +
    BOUNCE_RESERVE_SLOTS;
  assign primary_slot_open =
    (effective_work_count + reserved_bounce_slots < WORK_FIFO_DEPTH);

  assign ray_ready = !pending_primary_valid && primary_slot_open;

  always_comb begin
    intx_idle_found = 1'b0;
    launch_lane_idx = '0;
    for (int lane_sel = 0; lane_sel < NUM_INTERSECTORS; lane_sel = lane_sel + 1) begin
      if (!intx_idle_found && !intx_active[lane_sel]) begin
        intx_idle_found = 1'b1;
        launch_lane_idx = LANE_IDX_BITS'(lane_sel);
      end
    end
  end

  assign intx_done_mask = intx_active & ray_done_intx;

  always_comb begin
    intx_done_found = 1'b0;
    done_lane_idx = '0;
    done_ctx_bits = '0;
    done_hit_mat_idx = '0;
    done_hit_pos = '0;
    done_hit_norm = '0;
    done_hit_any = 1'b0;

    for (int lane_sel = 0; lane_sel < NUM_INTERSECTORS; lane_sel = lane_sel + 1) begin
      if (!intx_done_found && intx_done_mask[lane_sel]) begin
        intx_done_found = 1'b1;
        done_lane_idx = LANE_IDX_BITS'(lane_sel);
        done_ctx_bits = intx_ctx_bits[lane_sel];
        done_hit_mat_idx = intx_hit_mat_idx[lane_sel];
        done_hit_pos = intx_hit_pos[lane_sel];
        done_hit_norm = intx_hit_norm[lane_sel];
        done_hit_any = intx_hit_any[lane_sel];
      end
    end
  end

  always_comb begin
    work_write = 1'b0;
    enqueue_ctx_bits = '0;
    enqueue_from_pending_primary = 1'b0;
    enqueue_from_pending_bounce = 1'b0;
    enqueue_from_primary_now = 1'b0;
    enqueue_from_bounce_now = 1'b0;

    if (pending_bounce_valid && work_can_write) begin
      work_write = 1'b1;
      enqueue_ctx_bits = pending_bounce_bits;
      enqueue_from_pending_bounce = 1'b1;
    end else if (bounce_now_valid && work_can_write) begin
      work_write = 1'b1;
      enqueue_ctx_bits = bounce_ctx_bits;
      enqueue_from_bounce_now = 1'b1;
    end else if (pending_primary_valid && work_can_write) begin
      work_write = 1'b1;
      enqueue_ctx_bits = pending_primary_bits;
      enqueue_from_pending_primary = 1'b1;
    end else if (primary_now_valid && primary_slot_open && work_can_write) begin
      work_write = 1'b1;
      enqueue_ctx_bits = primary_ctx_bits;
      enqueue_from_primary_now = 1'b1;
    end
  end

  assign primary_capture_pending = primary_now_valid && !enqueue_from_primary_now;
  assign bounce_capture_pending = bounce_now_valid && !enqueue_from_bounce_now;

  assign capture_reflector = intx_done_found && done_hit_any;
  assign launch_reflector = reflect_valid;
  assign reflect_meta_in_bits = {
    reflect_ctx_pixel_h,
    reflect_ctx_pixel_v,
    reflect_ctx_bounce_count
  };

  pipeline #(
    .WIDTH(REFLECT_META_BITS),
    .DEPTH(REFLECT_DONE_DELAY)
  ) reflect_meta_pipe (
    .clk(clk),
    .in(reflect_meta_in_bits),
    .out(reflect_meta_out_bits)
  );

  assign miss_result_now_valid = intx_done_found && !done_hit_any;
  assign miss_result_now_bits = {
    done_ctx_pixel_h,
    done_ctx_pixel_v,
    done_ctx_income_light
  };

  assign reflect_result_now_valid = ray_done_reflect && reflect_is_final;
  assign reflect_result_now_bits = {
    reflect_meta_pixel_h,
    reflect_meta_pixel_v,
    rflx_new_income_light
  };

  assign result_head_bits = result_fifo_mem[result_read_ptr];
  assign result_empty = (result_count == 0);
  assign result_pop = !result_empty;
  assign result_push_count = miss_result_now_valid + reflect_result_now_valid;
  assign result_push0_bits = miss_result_now_valid ? miss_result_now_bits : reflect_result_now_bits;
  assign result_write_ptr_after_push0 = result_next_ptr(result_write_ptr);

  generate
    for (lane_idx = 0; lane_idx < NUM_INTERSECTORS; lane_idx = lane_idx + 1) begin : gen_ray_intx
      assign {
        intx_ctx_pixel_h[lane_idx],
        intx_ctx_pixel_v[lane_idx],
        intx_ctx_ray_origin[lane_idx],
        intx_ctx_ray_dir[lane_idx],
        intx_ctx_income_light[lane_idx],
        intx_ctx_ray_color[lane_idx],
        intx_ctx_bounce_count[lane_idx]
      } = intx_ctx_bits[lane_idx];

      ray_intersector ray_intx (
        .clk(clk),
        .rst(rst),
        .ray_origin(intx_ctx_ray_origin[lane_idx]),
        .ray_dir(intx_ctx_ray_dir[lane_idx]),
        .ray_valid(ray_valid_intx[lane_idx]),
        .hit_mat_idx(intx_hit_mat_idx[lane_idx]),
        .hit_pos(intx_hit_pos[lane_idx]),
        .hit_normal(intx_hit_norm[lane_idx]),
        .hit_dist(),
        .hit_any(intx_hit_any[lane_idx]),
        .hit_valid(ray_done_intx[lane_idx]),
        .num_objs(num_objs),
        .obj(obj)
      );
    end
  endgenerate

  ray_reflector ray_reflect (
    .clk(clk),
    .rst(rst),
    .ray_dir(reflect_ctx_ray_dir),
    .ray_color(reflect_ctx_ray_color),
    .income_light(reflect_ctx_income_light),
    .lfsr_seed(lfsr_seed),
    .hit_pos(reflect_hit_pos),
    .hit_normal(reflect_hit_norm),
    .hit_mat_idx(reflect_hit_mat_idx),
    .hit_valid(launch_reflector),
    .new_dir(rflx_new_dir),
    .new_origin(rflx_new_origin),
    .new_color(rflx_new_color),
    .new_income_light(rflx_new_income_light),
    .reflect_done(ray_done_reflect),
    .mat_dict_idx(mat_dict_idx),
    .mat_dict_mat(mat_dict_mat)
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      ray_valid_intx <= '0;
      intx_active <= '0;
      for (lane = 0; lane < NUM_INTERSECTORS; lane = lane + 1) begin
        intx_ctx_bits[lane] <= '0;
      end

      work_read_ptr <= '0;
      work_write_ptr <= '0;
      work_count <= '0;

      pending_primary_valid <= 1'b0;
      pending_primary_bits <= '0;
      pending_bounce_valid <= 1'b0;
      pending_bounce_bits <= '0;
      reflect_valid <= 1'b0;
      reflect_ctx_bits <= '0;
      reflect_hit_mat_idx <= '0;
      reflect_hit_pos <= '0;
      reflect_hit_norm <= '0;
      reflect_inflight_count <= '0;

      result_read_ptr <= '0;
      result_write_ptr <= '0;
      result_count <= '0;

      ray_done <= 1'b0;
      pixel_color <= '0;
      pixel_h_out <= '0;
      pixel_v_out <= '0;
    end else begin
      ray_valid_intx <= '0;
      ray_done <= 1'b0;

      if (work_write) begin
        work_fifo_mem[work_write_ptr] <= enqueue_ctx_bits;
      end

      case ({work_read, work_write})
        2'b10: begin
          work_read_ptr <= fifo_next_ptr(work_read_ptr);
          work_count <= work_count - 1'b1;
        end
        2'b01: begin
          work_write_ptr <= fifo_next_ptr(work_write_ptr);
          work_count <= work_count + 1'b1;
        end
        2'b11: begin
          work_read_ptr <= fifo_next_ptr(work_read_ptr);
          work_write_ptr <= fifo_next_ptr(work_write_ptr);
        end
        default: begin
        end
      endcase

      if (enqueue_from_pending_primary) begin
        pending_primary_valid <= 1'b0;
      end
      if (enqueue_from_pending_bounce) begin
        pending_bounce_valid <= 1'b0;
      end

      if (primary_capture_pending) begin
        pending_primary_valid <= 1'b1;
        pending_primary_bits <= primary_ctx_bits;
      end
      if (bounce_capture_pending) begin
        pending_bounce_valid <= 1'b1;
        pending_bounce_bits <= bounce_ctx_bits;
      end

      reflect_valid <= 1'b0;
      reflect_ctx_bits <= '0;
      reflect_hit_mat_idx <= '0;
      reflect_hit_pos <= '0;
      reflect_hit_norm <= '0;
      if (capture_reflector) begin
        reflect_valid <= 1'b1;
        reflect_ctx_bits <= done_ctx_bits;
        reflect_hit_mat_idx <= done_hit_mat_idx;
        reflect_hit_pos <= done_hit_pos;
        reflect_hit_norm <= done_hit_norm;
      end

      if (launch_reflector && !ray_done_reflect) begin
        reflect_inflight_count <= reflect_inflight_count + 1'b1;
      end else if (!launch_reflector && ray_done_reflect) begin
        reflect_inflight_count <= reflect_inflight_count - 1'b1;
      end

      if (work_read) begin
        intx_ctx_bits[launch_lane_idx] <= work_head_bits;
        intx_active[launch_lane_idx] <= 1'b1;
        ray_valid_intx[launch_lane_idx] <= 1'b1;
      end

      if (intx_done_found) begin
        intx_active[done_lane_idx] <= 1'b0;
      end

      if (miss_result_now_valid) begin
        result_fifo_mem[result_write_ptr] <= miss_result_now_bits;
      end
      if (reflect_result_now_valid) begin
        result_fifo_mem[miss_result_now_valid ? result_write_ptr_after_push0 : result_write_ptr] <= reflect_result_now_bits;
      end

      if (result_pop) begin
        ray_done <= 1'b1;
        {
          pixel_h_out,
          pixel_v_out,
          pixel_color
        } <= result_head_bits;
      end

      if (result_pop) begin
        result_read_ptr <= result_next_ptr(result_read_ptr);
      end
      if (result_push_count != 0) begin
        if (result_push_count == 2) begin
          result_write_ptr <= result_next_ptr(result_write_ptr_after_push0);
        end else begin
          result_write_ptr <= result_write_ptr_after_push0;
        end
      end

      case ({result_pop, result_push_count})
        3'b000: begin
        end
        3'b001: begin
          result_count <= result_count + 1'b1;
        end
        3'b010: begin
          result_count <= result_count + 2'd2;
        end
        3'b100: begin
          result_count <= result_count - 1'b1;
        end
        3'b101: begin
          result_count <= result_count;
        end
        3'b110: begin
          result_count <= result_count + 1'b1;
        end
        default: begin
        end
      endcase
    end
  end
endmodule

`default_nettype wire
