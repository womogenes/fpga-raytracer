`default_nettype none

module fp_vec3_dot_fast (
  input wire clk,
  input wire rst,
  input fp_vec3 v,
  input fp_vec3 w,
  output fp dot
);
  fp_vec3 prod;
  fp sum_xy;
  fp z_piped;

  fp_vec3_mul mul(.clk(clk), .rst(rst), .v(v), .w(w), .prod(prod));
  fp_add_fast add_xy(.clk(clk), .rst(rst), .a(prod.x), .b(prod.y), .is_sub(1'b0), .sum(sum_xy));
  pipeline #(.WIDTH(FP_BITS), .DEPTH(1)) z_pipe (.clk(clk), .in(prod.z), .out(z_piped));
  fp_add_fast add_xyz(.clk(clk), .rst(rst), .a(sum_xy), .b(z_piped), .is_sub(1'b0), .sum(dot));
endmodule

`default_nettype wire
