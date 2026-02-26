`default_nettype none

module fp_add_fast (
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

  function automatic logic fp_abs_greater_fast(input fp lhs, input fp rhs);
    begin
      fp_abs_greater_fast = (lhs.exp > rhs.exp) || ((lhs.exp == rhs.exp) && (lhs.mant > rhs.mant));
    end
  endfunction

  function automatic [SHIFT_WIDTH-1:0] lzd17(input logic [SIG_WIDTH-1:0] value);
    begin
      casez (value)
        17'b1????????????????: lzd17 = 5'd0;
        17'b01???????????????: lzd17 = 5'd1;
        17'b001??????????????: lzd17 = 5'd2;
        17'b0001?????????????: lzd17 = 5'd3;
        17'b00001????????????: lzd17 = 5'd4;
        17'b000001???????????: lzd17 = 5'd5;
        17'b0000001??????????: lzd17 = 5'd6;
        17'b00000001?????????: lzd17 = 5'd7;
        17'b000000001????????: lzd17 = 5'd8;
        17'b0000000001???????: lzd17 = 5'd9;
        17'b00000000001??????: lzd17 = 5'd10;
        17'b000000000001?????: lzd17 = 5'd11;
        17'b0000000000001????: lzd17 = 5'd12;
        17'b00000000000001???: lzd17 = 5'd13;
        17'b000000000000001??: lzd17 = 5'd14;
        17'b0000000000000001?: lzd17 = 5'd15;
        17'b00000000000000001: lzd17 = 5'd16;
        default: lzd17 = 5'd17;
      endcase
    end
  endfunction

  logic swap;
  logic [FP_EXP_BITS-1:0] exp_a, exp_b, exp_norm;
  logic sign_a, sign_b;
  logic [FP_MANT_BITS-1:0] mant_a, mant_b;
  logic [FRAC_WIDTH-1:0] frac_a, frac_b, frac_b_shift, frac_sum;
  logic [SIG_WIDTH-1:0] frac_norm;
  logic [FP_EXP_BITS-1:0] exp_diff;
  logic [SHIFT_WIDTH-1:0] shift_amt;
  logic both_zero;
  logic sum_is_zero;
  logic [FP_BITS-1:0] sum_next;

  assign swap = ~fp_abs_greater_fast(a, b);

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
  assign shift_amt = lzd17(frac_sum[SIG_WIDTH-1:0]);

  always_comb begin
    if (exp_diff > (FP_MANT_BITS + 1)) begin
      frac_b_shift = '0;
    end else begin
      frac_b_shift = frac_b >> exp_diff;
    end
    frac_sum = (sign_a == sign_b) ? (frac_a + frac_b_shift) : (frac_a - frac_b_shift);
    sum_is_zero = (frac_sum == '0);
  end

  always_comb begin
    frac_norm = '0;
    exp_norm = '0;
    sum_next = FP_ZER0;
    if (both_zero || sum_is_zero) begin
    end else if (frac_sum[FRAC_WIDTH-1]) begin
      frac_norm = frac_sum[FRAC_WIDTH-1:1];
      exp_norm = exp_a + 1'b1;
      sum_next = {sign_a, exp_norm, frac_norm[FP_MANT_BITS-1:0]};
    end else if (exp_a <= shift_amt) begin
      sum_next = FP_ZER0;
    end else begin
      frac_norm = frac_sum[SIG_WIDTH-1:0] << shift_amt;
      exp_norm = exp_a - shift_amt;
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

`default_nettype wire
