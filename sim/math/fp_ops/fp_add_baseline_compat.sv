`default_nettype none

function automatic logic fp_greater_baseline(fp a, fp b);
  logic greater;
  greater = (a.exp > b.exp) || (a.exp == b.exp && a.mant > b.mant);
  return greater;
endfunction

module fp_add_baseline (
  input wire clk,
  input wire rst,
  input fp a,
  input fp b,
  input wire is_sub,

  output fp sum
);
  logic swap;
  assign swap = ~fp_greater_baseline(a, b);

  logic [FP_EXP_BITS-1:0] exp_a, exp_b;
  logic sign_a, sign_b;
  logic [FP_MANT_BITS-1:0] mant_a, mant_b;
  logic [FP_MANT_BITS+1:0] frac_a, frac_b;

  assign exp_a = swap ? b.exp : a.exp;
  assign exp_b = swap ? a.exp : b.exp;

  assign sign_a = swap ? (b.sign ^ is_sub) : a.sign;
  assign sign_b = swap ? a.sign : (b.sign ^ is_sub);

  assign mant_a = swap ? b.mant : a.mant;
  assign mant_b = swap ? a.mant : b.mant;

  assign frac_a = {2'b01, mant_a};
  assign frac_b = {2'b01, mant_b};

  logic [FP_EXP_BITS-1:0] exp_diff;
  logic [FP_MANT_BITS+1:0] frac_b_shift;
  logic [FP_MANT_BITS:0] frac_norm;
  logic [FP_EXP_BITS-1:0] exp_norm;
  logic [$clog2(FP_MANT_BITS+1):0] shift;

  logic sign_a_buf;
  logic [FP_EXP_BITS-1:0] exp_a_buf;
  logic [FP_MANT_BITS+1:0] frac_sum_buf;
  logic both_zero;

  always_comb begin
    exp_diff = exp_a - exp_b;
    frac_b_shift = frac_b >> exp_diff;
  end

  always_ff @(posedge clk) begin
    frac_sum_buf <= (sign_a == sign_b) ? (frac_a + frac_b_shift) : (frac_a - frac_b_shift);
    exp_a_buf <= exp_a;
    sign_a_buf <= sign_a;
    both_zero <= (exp_a == 0 && mant_a == 0 && exp_b == 0 && mant_b == 0);
  end

  clz #(.WIDTH(FP_MANT_BITS+1)) clz_shift (.x(frac_sum_buf[FP_MANT_BITS:0]), .count(shift));

  always_comb begin
    if (frac_sum_buf[FP_MANT_BITS+1]) begin
      frac_norm = frac_sum_buf[FP_MANT_BITS+1:1];
      exp_norm = exp_a_buf + 1;
    end else begin
      frac_norm = frac_sum_buf[FP_MANT_BITS:0] << shift;
      exp_norm = exp_a_buf - shift;
    end
  end

  always_ff @(posedge clk) begin
    sum <= both_zero ? 0 : {sign_a_buf, exp_norm, frac_norm[FP_MANT_BITS-1:0]};
  end
endmodule

`default_nettype wire
