`default_nettype none

module picorv32_tb (
  input wire clk,
  input wire rst,

  // Memory interface
  output logic mem_valid,
  output logic mem_instr,   // high if instruction fetch
  input wire mem_ready,
  output logic [31:0] mem_addr,
  output logic [31:0] mem_wdata,
  output logic [ 3:0] mem_wstrb,  // memory write strobe (wstrb) for LH, LB, etc
  input wire  [31:0] mem_rdata   // read data from memory module
);
  // Do stuff
  picorv32 #(
    .REGS_INIT_ZERO(1),
    .STACKADDR(32'h ffff_ffff)
  ) cpu (
    .clk(clk),
    .resetn(~rst),

    // Memory interface
    .mem_valid(mem_valid),
    .mem_instr(mem_instr),
    .mem_ready(mem_ready),
    .mem_addr(mem_addr),
    .mem_wdata(mem_wdata),
    .mem_wstrb(mem_wstrb),
    .mem_rdata(mem_rdata)
  );
endmodule

`default_nettype wire
