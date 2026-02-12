// Alu functions
typedef enum logic [3:0] { ADD, SUB, AND, OR, XOR, SLT, SLTU, SLL, SRL, SRA } AluFunc;

// Instruction type enumeration
typedef enum logic [3:0] { OP, OPIMM, BRANCH, LUI, JAL, JALR, LOAD, STORE, AUIPC, MUL, Unsupported } IType;

// Branch type enumeration
typedef enum logic [2:0] { EQ, NEQ, LT, LTU, GE, GEU } BrFunc;

// Branch function enumeration
typedef struct packed {
  IType itype;
  AluFunc alu_func;    // comes from alu.sv
  BrFunc br_func;      // branch operation
  MemFunc mem_func;    // memory operation
  logic [4:0] dst;    // register to write to
  logic dst_valid;    // register dst write enable?
  logic [4:0] src1;   // register source index 1
  logic [4:0] src2;   // register source index 2
  Word imm;   // immediate values
} DecodedInst;

typedef struct packed {
  IType itype;
  MemFunc mem_func;
  logic [4:0] dst;
  logic dst_valid;
  Word data;
  Word addr;
  Word next_pc;
} ExecInst;

// Opcodes
parameter logic [6:0] op_OPIMM    = 7'b0010011;
parameter logic [6:0] op_OP       = 7'b0110011;
parameter logic [6:0] op_LUI      = 7'b0110111;
parameter logic [6:0] op_JAL      = 7'b1101111;
parameter logic [6:0] op_JALR     = 7'b1100111;
parameter logic [6:0] op_BRANCH   = 7'b1100011;
parameter logic [6:0] op_LOAD     = 7'b0000011;
parameter logic [6:0] op_STORE    = 7'b0100011;
parameter logic [6:0] op_AUIPC    = 7'b0010111;

// funct3 - ALU functions
parameter logic [2:0] fn_ADD  = 3'b000;
parameter logic [2:0] fn_SLL  = 3'b001;
parameter logic [2:0] fn_SLT  = 3'b010;
parameter logic [2:0] fn_SLTU = 3'b011;
parameter logic [2:0] fn_XOR  = 3'b100;
parameter logic [2:0] fn_SR   = 3'b101;
parameter logic [2:0] fn_OR   = 3'b110;
parameter logic [2:0] fn_AND  = 3'b111;

// funct3 - Branch
parameter logic [2:0] fn_BEQ  = 3'b000;
parameter logic [2:0] fn_BNE  = 3'b001;
parameter logic [2:0] fn_BLT  = 3'b100;
parameter logic [2:0] fn_BGE  = 3'b101;
parameter logic [2:0] fn_BLTU = 3'b110;
parameter logic [2:0] fn_BGEU = 3'b111;

// funct3 - Load
parameter logic [2:0] fn_LW   = 3'b010;
parameter logic [2:0] fn_LB   = 3'b000;
parameter logic [2:0] fn_LH   = 3'b001;
parameter logic [2:0] fn_LBU  = 3'b100;
parameter logic [2:0] fn_LHU  = 3'b101;

// funct3 - Store
parameter logic [2:0] fn_SW   = 3'b010;
parameter logic [2:0] fn_SB   = 3'b000;
parameter logic [2:0] fn_SH   = 3'b001;

// funct3 - JALR
parameter logic [2:0] fn_JALR = 3'b000;
