`default_nettype none

module ray_intersector (
  input wire clk,
  input wire rst,
  input fp_vec3 ray_origin,
  input fp_vec3 ray_dir,
  input wire ray_valid,

  output logic [7:0] hit_mat_idx,
  output fp_vec3 hit_pos,
  output fp_vec3 hit_normal,
  output fp hit_dist,
  output logic hit_any,
  output logic hit_valid,

  input wire [$clog2(MAX_NUM_OBJS)-1:0] num_objs,
  input object obj
);
  logic [$clog2(MAX_NUM_OBJS + 1)-1:0] pre_obj_count;
  logic [$clog2(MAX_NUM_OBJS + 1)-1:0] post_obj_count;
  logic last_obj;
  logic processing_obj;

  logic ray_valid_piped;
  pipeline #(
    .WIDTH(1),
    .DEPTH(SPHERE_INTX_DELAY)
  ) ray_valid_pipe (
    .clk(clk),
    .in(ray_valid),
    .out(ray_valid_piped)
  );

  assign processing_obj =
    (ray_valid_piped === 1'b1) ||
    ((num_objs > 1) && (post_obj_count < num_objs - 1));
  assign last_obj = (num_objs != 0) && (
    ((ray_valid_piped === 1'b1) && (num_objs == 1)) ||
    ((num_objs > 1) && (ray_valid_piped === 1'b0) && (post_obj_count == num_objs - 2))
  );

  logic sphere_intx_hit;
  fp_vec3 sphere_intx_hit_pos;
  fp sphere_intx_hit_dist;
  fp_vec3 sphere_intx_hit_norm;

  logic trig_intx_hit_prepipe;
  fp_vec3 trig_intx_hit_pos_prepipe;
  fp trig_intx_hit_dist_prepipe;
  fp_vec3 trig_intx_hit_norm_prepipe;

  logic trig_intx_hit;
  fp_vec3 trig_intx_hit_pos;
  fp trig_intx_hit_dist;
  fp_vec3 trig_intx_hit_norm;

  logic [7:0] obj_intx_mat_idx;
  pipeline #(
    .WIDTH(8),
    .DEPTH(SPHERE_INTX_DELAY)
  ) mat_idx_pipe (
    .clk(clk),
    .in(obj.mat_idx),
    .out(obj_intx_mat_idx)
  );

  logic [1:0] obj_type_piped;
  pipeline #(
    .WIDTH(2),
    .DEPTH(SPHERE_INTX_DELAY)
  ) obj_type_pipe (
    .clk(clk),
    .in(obj.obj_type),
    .out(obj_type_piped)
  );

  sphere sphere_cast;
  assign sphere_cast = obj.stuff;

  sphere_intersector sphere_intx (
    .clk(clk),
    .rst(rst),
    .ray_origin(ray_origin),
    .ray_dir(ray_dir),
    .sphere_center(sphere_cast.sphere_center),
    .sphere_rad_sq(sphere_cast.sphere_rad_sq),
    .sphere_rad_inv(sphere_cast.sphere_rad_inv),
    .hit(sphere_intx_hit),
    .hit_pos(sphere_intx_hit_pos),
    .hit_dist(sphere_intx_hit_dist),
    .hit_norm(sphere_intx_hit_norm)
  );

  trig trig_cast;
  assign trig_cast = obj.stuff;

  trig_intersector trig_intx (
    .clk(clk),
    .rst(rst),
    .ray_origin(ray_origin),
    .ray_dir(ray_dir),
    .v0(trig_cast.points[2]),
    .v0v1(trig_cast.points[1]),
    .v0v2(trig_cast.points[0]),
    .normal(trig_cast.normal),
    .obj_type(obj.obj_type),
    .hit(trig_intx_hit_prepipe),
    .hit_pos(trig_intx_hit_pos_prepipe),
    .hit_dist(trig_intx_hit_dist_prepipe),
    .hit_norm(trig_intx_hit_norm_prepipe)
  );

  generate
    if (SPHERE_INTX_DELAY > TRIG_INTX_DELAY) begin : gen_trig_pipe
      pipeline #(
        .WIDTH(1 + $bits(fp_vec3) + $bits(fp_vec3) + $bits(fp)),
        .DEPTH(SPHERE_INTX_DELAY - TRIG_INTX_DELAY)
      ) trig_inx_pipe (
        .clk(clk),
        .in({
          trig_intx_hit_prepipe,
          trig_intx_hit_pos_prepipe,
          trig_intx_hit_dist_prepipe,
          trig_intx_hit_norm_prepipe
        }),
        .out({
          trig_intx_hit,
          trig_intx_hit_pos,
          trig_intx_hit_dist,
          trig_intx_hit_norm
        })
      );
    end else begin : gen_trig_bypass
      assign trig_intx_hit = trig_intx_hit_prepipe;
      assign trig_intx_hit_pos = trig_intx_hit_pos_prepipe;
      assign trig_intx_hit_dist = trig_intx_hit_dist_prepipe;
      assign trig_intx_hit_norm = trig_intx_hit_norm_prepipe;
    end
  endgenerate

  always_ff @(posedge clk) begin
    if (rst) begin
      hit_valid <= 1'b0;
      hit_pos <= 0;
      hit_any <= 1'b0;
      hit_dist <= 1'b0;
      pre_obj_count <= num_objs;
      post_obj_count <= num_objs;
    end else begin
      if (ray_valid) begin
        pre_obj_count <= 0;
      end else if (pre_obj_count < num_objs) begin
        pre_obj_count <= pre_obj_count + 1;
      end

      if (ray_valid_piped) begin
        post_obj_count <= 0;
      end else if (post_obj_count < num_objs) begin
        post_obj_count <= post_obj_count + 1;
      end

      if (processing_obj) begin
        if (obj_type_piped != 2'b00) begin
          if (ray_valid_piped) begin
            if (trig_intx_hit) begin
              hit_mat_idx <= obj_intx_mat_idx;
              hit_pos <= trig_intx_hit_pos;
              hit_normal <= trig_intx_hit_norm;
              hit_dist <= trig_intx_hit_dist;
              hit_any <= 1'b1;
            end else begin
              hit_any <= 1'b0;
            end
          end else if (trig_intx_hit && (hit_any == 0 || fp_greater(hit_dist, trig_intx_hit_dist))) begin
            hit_mat_idx <= obj_intx_mat_idx;
            hit_pos <= trig_intx_hit_pos;
            hit_normal <= trig_intx_hit_norm;
            hit_dist <= trig_intx_hit_dist;
            hit_any <= 1'b1;
          end
        end else begin
          if (ray_valid_piped) begin
            if (sphere_intx_hit) begin
              hit_mat_idx <= obj_intx_mat_idx;
              hit_pos <= sphere_intx_hit_pos;
              hit_normal <= sphere_intx_hit_norm;
              hit_dist <= sphere_intx_hit_dist;
              hit_any <= 1'b1;
            end else begin
              hit_any <= 1'b0;
            end
          end else if (sphere_intx_hit && (hit_any == 0 || fp_greater(hit_dist, sphere_intx_hit_dist))) begin
            hit_mat_idx <= obj_intx_mat_idx;
            hit_pos <= sphere_intx_hit_pos;
            hit_normal <= sphere_intx_hit_norm;
            hit_dist <= sphere_intx_hit_dist;
            hit_any <= 1'b1;
          end
        end
      end

      hit_valid <= last_obj;
    end
  end

endmodule

`default_nettype wire
