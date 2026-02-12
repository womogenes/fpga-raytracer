// Processor, pipelined

`default_nettype none

// A bunch of types
typedef enum logic [2:0] { DEQUEUE, STALL, REDIRECT } FetchAction;
typedef struct packed {
  FetchAction fetch_action;
  Word redirect_pc; // PC to fetch from, used only if fetch_action is REDIRECT
} FetchInput;

typedef struct packed {
  Word pc;
  DecodedInst dinst;
  Word r_val1;
  Word r_val2;
} D2E;

typedef struct packed {
  Word pc;
  IType itype;
  logic [4:0] dst;
  logic dst_valid;
  Word data;
} E2W;

module processor (
  input wire clk,
  input wire rst
);
  // program counter
  Word pc;

  // Memory output
  Word mem_data_a;
  logic mem_data_a_valid;

  Word mem_data_b;
  logic mem_data_b_valid;

  // Mem write enabled
  logic mem_w_en;

  // Encoded and decoded instruction
  Word inst;
  DecodedInst dinst;
  logic [4:0] src1;   // port for register file
  logic [4:0] src2;   // port for register file
  Word r_val1;
  Word r_val2;

  // REGISTER FILE
  reg_file(
    .clk(clk),
    .rst(rst),
    .src1(src1),
    .src2(src2),
    .w_en(einst.dst_valid),
    .w_idx(einst.dst),
    .w_data(einst.data),
    .dout1(r_val1),
    .dout2(r_val2)
  );

  // Execute instruction
  ExecInst einst;

  // FETCH STAGE
  main_memory(
    // PORT A (instruction)
    .clk(clk),
    .rst(rst),
    .addra(pc),
    .douta(mem_data_a),
    .dout_valid(mem_data_a_valid),
    .w_en(1'b0),
    .r_en(1'b1),

    // PORT B (data)
    .addrb(),
    .dinb(),
    .w_enb(),
    .r_enb()
  );

  // DECODE STAGE
  // Load instruction of valid a
  always_ff @(posedge clk) begin
    if (mem_data_a_valid) begin
      inst <= mem_data_a;
    end
  end

  decoder(
    .inst(inst),
    .dinst(dinst)
  );

  // EXECUTE STAGE
  execute(
    .dinst(dinst),
    .r_val1(r_val1),
    .r_val2(r_val2),
    .pc(pc),
    .einst(einst)
  );

  // WRITEBACK STAGE
  always_ff @(posedge clk) begin
    if (einst.dst_valid) begin
      
    end
  end

endmodule

`default_nettype wire
