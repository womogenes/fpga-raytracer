// Register file!!

`default_nettype none

module reg_file(
  input wire clk,
  // do not allow resets because that's slow af

  // dual-port reads
  input wire [4:0] r_idx1,        // read register index 1
  input wire [4:0] r_idx2,        // read register index 2

  // single-port writes
  input wire w_en,                // write enable
  input wire [4:0] w_idx,         // write register index
  input Word w_data,       // write data

  output Word dout1,      // data out 1
  output Word dout2       // data out 2
);
  // 32 registers (except 0 is always 0)
  Word reg_data [31:0];

  always_comb begin
    // look for registers
    if (r_idx1 == 0) dout1 = 0;
    if (r_idx2 == 0) dout2 = 0;

    for (integer i = 1; i < 32; i = i + 1) begin
      if (r_idx1 == i) dout1 = reg_data[i];
      if (r_idx2 == i) dout2 = reg_data[i];
    end
  end

  always_ff @(posedge clk) begin
    // write to write_reg_idx IF it is not zero
    if (w_en && w_idx != 0) begin
      reg_data[w_idx] <= w_data;
    end
  end
endmodule

`default_nettype wire
