`default_nettype none

module fp_vec3_normalize_baseline (
  input wire clk,
  input wire rst,
  input fp_vec3 v,
  output fp_vec3 normed
);
  fp mag_sq;
  fp mag_inv;
  fp_vec3 v_piped;

  fp_vec3_dot_baseline dot_mag_sq(.clk(clk), .rst(rst), .v(v), .w(v), .dot(mag_sq));
  fp_inv_sqrt_baseline inv_sqrt_mag(
    .clk(clk),
    .rst(rst),
    .x(mag_sq),
    .x_valid(1'b1),
    .inv_sqrt(mag_inv),
    .inv_sqrt_valid()
  );
  pipeline #(.WIDTH(FP_VEC3_BITS), .DEPTH(15)) v_pipe(.clk(clk), .in(v), .out(v_piped));
  fp_vec3_scale scale_a_norm(.clk(clk), .rst(rst), .v(v_piped), .s(mag_inv), .scaled(normed));
endmodule

`default_nettype wire
