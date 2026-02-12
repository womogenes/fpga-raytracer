`default_nettype none

module execute_tb (
  input wire [31:0] inst,
  input wire [31:0] r_val1,     // value from register rs1
  input wire [31:0] r_val2,     // value from register rs2
  input wire [31:0] pc,         // program counter

  output ExecInst einst         // executed instruction
);

  // instantiate a decode module
  DecodedInst dinst;
  decoder my_decoder(.inst(inst), .dinst(dinst));

  // instantiate an execute module
  execute my_execute(.dinst(dinst), .r_val1(r_val1), .r_val2(r_val2), .pc(pc), .einst(einst));
endmodule;

`default_nettype wire
