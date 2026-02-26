`default_nettype none

module fp_vec3_add_fast (
  input wire clk,
  input wire rst,
  input fp_vec3 v,
  input fp_vec3 w,
  input wire is_sub,
  output fp_vec3 sum
);
  fp_add_fast add_x(.clk(clk), .rst(rst), .a(v.x), .b(w.x), .is_sub(is_sub), .sum(sum.x));
  fp_add_fast add_y(.clk(clk), .rst(rst), .a(v.y), .b(w.y), .is_sub(is_sub), .sum(sum.y));
  fp_add_fast add_z(.clk(clk), .rst(rst), .a(v.z), .b(w.z), .is_sub(is_sub), .sum(sum.z));
endmodule

`default_nettype wire
