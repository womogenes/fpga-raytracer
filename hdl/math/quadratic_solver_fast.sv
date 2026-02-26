`default_nettype none

module quadratic_solver_fast (
  input wire clk,
  input wire rst,
  input fp b,
  input fp c,
  output fp x0,
  output logic valid
);
  localparam integer SQRT_FAST_DELAY = (INV_SQRT_NR_STAGES * 4) + 1;

  fp b_sq;
  fp four_c;
  fp four_c_shifted;
  fp discr;
  fp sqrt_discr;
  fp b_piped;
  fp neg_b_piped;
  fp numer;

  fp_mul mul_b_sq(.clk(clk), .rst(rst), .a(b), .b(b), .prod(b_sq));
  fp_shift #(.SHIFT_AMT(2)) shift_four_c(.a(c), .shifted(four_c_shifted));

  always_ff @(posedge clk) begin
    four_c <= four_c_shifted;
  end

  fp_add_fast add_discr(.clk(clk), .rst(rst), .a(b_sq), .b(four_c), .is_sub(1'b1), .sum(discr));

  fp_sqrt_fast sqrt_discr_inst(.clk(clk), .rst(rst), .x(discr), .sqrt(sqrt_discr));
  pipeline #(.WIDTH(FP_BITS), .DEPTH(SQRT_FAST_DELAY + 2)) b_pipe (.clk(clk), .in(b), .out(b_piped));

  assign neg_b_piped = {~b_piped[FP_BITS-1], b_piped[FP_BITS-2:0]};
  fp_add_fast add_numer(.clk(clk), .rst(rst), .a(neg_b_piped), .b(sqrt_discr), .is_sub(1'b1), .sum(numer));
  fp_shift #(.SHIFT_AMT(-1)) shift_x0(.a(numer), .shifted(x0));

  pipeline #(.WIDTH(1), .DEPTH(SQRT_FAST_DELAY + 1)) valid_pipe (
    .clk(clk),
    .in(~discr[FP_BITS-1]),
    .out(valid)
  );
endmodule

`default_nettype wire
