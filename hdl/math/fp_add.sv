// Hepler function: compare two floats
function automatic logic fp_greater(fp a, fp b);
  logic greater;
  greater = (a.exp > b.exp) || (a.exp == b.exp && a.mant > b.mant);
  return greater;
endfunction

// Addition for floating points
module fp_add (
  input wire clk,
  input wire rst,
  input fp a,
  input fp b,
  input wire is_sub,

  output fp sum
);
  localparam integer SIG_WIDTH = FP_MANT_BITS + 1;
  localparam integer FRAC_WIDTH = FP_MANT_BITS + 2;
  localparam integer SHIFT_WIDTH = $clog2(SIG_WIDTH + 1);

  logic swap;
  assign swap = ~fp_greater(a, b);

  logic [FP_EXP_BITS-1:0] exp_a, exp_b, exp_norm;
  logic sign_a, sign_b;
  logic [FP_MANT_BITS-1:0] mant_a, mant_b;
  logic [FRAC_WIDTH-1:0] frac_a, frac_b, frac_b_shift, frac_sum;
  logic [SIG_WIDTH-1:0] frac_norm;
  logic [FP_EXP_BITS-1:0] exp_diff;
  logic [SHIFT_WIDTH-1:0] shift;
  logic both_zero;
  logic sum_is_zero;
  logic [FP_BITS-1:0] sum_next;

  assign exp_a = swap ? b.exp : a.exp;
  assign exp_b = swap ? a.exp : b.exp;
  assign sign_a = swap ? (b.sign ^ is_sub) : a.sign;
  assign sign_b = swap ? a.sign : (b.sign ^ is_sub);
  assign mant_a = swap ? b.mant : a.mant;
  assign mant_b = swap ? a.mant : b.mant;
  assign frac_a = {2'b01, mant_a};
  assign frac_b = {2'b01, mant_b};
  assign exp_diff = exp_a - exp_b;
  assign both_zero = (exp_a == '0) && (mant_a == '0) && (exp_b == '0) && (mant_b == '0);

  always_comb begin
    if (exp_diff > (FP_MANT_BITS + 1)) begin
      frac_b_shift = '0;
    end else begin
      frac_b_shift = frac_b >> exp_diff;
    end
    frac_sum = (sign_a == sign_b) ? (frac_a + frac_b_shift) : (frac_a - frac_b_shift);
    sum_is_zero = (frac_sum == '0);
  end

  clz #(.WIDTH(SIG_WIDTH)) clz_shift (
    .x(frac_sum[SIG_WIDTH-1:0]),
    .count(shift)
  );

  always_comb begin
    frac_norm = '0;
    exp_norm = '0;
    sum_next = FP_ZER0;

    if (both_zero || sum_is_zero) begin
      sum_next = FP_ZER0;
    end else if (frac_sum[FRAC_WIDTH-1]) begin
      frac_norm = frac_sum[FRAC_WIDTH-1:1];
      exp_norm = exp_a + 1'b1;
      sum_next = {sign_a, exp_norm, frac_norm[FP_MANT_BITS-1:0]};
    end else if (exp_a <= shift) begin
      sum_next = FP_ZER0;
    end else begin
      frac_norm = frac_sum[SIG_WIDTH-1:0] << shift;
      exp_norm = exp_a - shift;
      sum_next = {sign_a, exp_norm, frac_norm[FP_MANT_BITS-1:0]};
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      sum <= FP_ZER0;
    end else begin
      sum <= sum_next;
    end
  end
endmodule
