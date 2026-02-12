`default_nettype none

// Branch ALU -- determine if we should branch based on inputs
//   and branch type.
module br_alu (
  input Word a,
  input Word b,
  input BrFunc br_func,
  output logic out
);
  always_comb begin
    case (br_func)
      EQ: out = (a == b);
      NEQ: out = (a != b);
      LT: out = ($signed(a) < $signed(b));
      LTU: out = (a < b);
      GE: out = ($signed(a) >= $signed(b));
      GEU: out = (a >= b);
      default: out = 1'b0;
    endcase
  end
endmodule

// Execute module
module execute (
  input DecodedInst dinst,
  input Word r_val1,     // value from register rs1
  input Word r_val2,     // value from register rs2
  input Word pc,         // program counter

  output ExecInst einst    // executed instruction
);
  Word imm;
  BrFunc br_func;
  AluFunc alu_func;
  Word alu_val2;

  // Assign these known values from decode stage
  assign imm = dinst.imm;
  assign br_func = dinst.br_func;
  assign alu_func = dinst.alu_func;
  assign alu_val2 = dinst.itype == OPIMM ? imm : r_val2;

  // Precompute stuff
  Word pc_plus_4;
  Word pc_plus_imm;

  assign pc_plus_4 = pc + 4;
  assign pc_plus_imm = pc + imm;

  // Data to pass on, etc.
  Word data;
  Word alu_out;
  logic br_alu_out;
  Word r_val1_plus_imm;
  Word next_pc;
  
  // Use the ALU
  alu(.a(r_val1), .b(alu_val2), .func(alu_func), .out(alu_out));

  // Do branching logic
  br_alu(.a(r_val1), .b(r_val2), .br_func(br_func), .out(br_alu_out));

  always_comb begin
    // Data to write to registers or to memory
    case (dinst.itype)
      AUIPC: data = pc_plus_imm;
      LUI: data = imm;
      OP, OPIMM: data = alu_out;
      JAL, JALR: data = pc_plus_4;
      STORE: data = r_val2;
      default: data = 'x;
    endcase

    // Branching logic
    r_val1_plus_imm = r_val1 + imm;
    case (dinst.itype)
      BRANCH: next_pc = br_alu_out ? pc_plus_imm : pc_plus_4;
      JAL: next_pc = pc_plus_imm;
      JALR: next_pc = r_val1_plus_imm & ~32'b1;  // clear out bottom bit
      default: next_pc = pc_plus_4;
    endcase

    // Return the right value
    einst.itype = dinst.itype;
    einst.dst = dinst.dst;
    einst.dst_valid = dinst.dst_valid;
    einst.data = data;
    einst.addr = r_val1_plus_imm;
    einst.next_pc = next_pc;
    einst.mem_func = dinst.mem_func;
  end
endmodule

`default_nettype wire
