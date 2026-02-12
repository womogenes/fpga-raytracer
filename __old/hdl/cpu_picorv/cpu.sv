// Uses picorv32 and memory to make a full CPU
// Handles MMIO

`default_nettype none

module cpu #(
  parameter INIT_FILE = ""
) (
  input wire clk,
  input wire rst,

  // Reprogramming interface
  input wire flash_active,
  input wire flash_wen,
  input wire [31:0] flash_addr,
  input wire [31:0] flash_data,

  // Output (second port on memory)
  input wire clk_mmio,
  input wire [31:0] mmio_addr,                  // word address
  output logic [31:0] mmio_rdata,
  input wire mmio_wen,
  input wire [31:0] mmio_wdata,

  // CPU internal state readout
  output logic trap,
  output logic cpu_mem_valid,
  output logic cpu_mem_instr,
  output logic [31:0] cpu_mem_addr,
  output logic [31:0] cpu_mem_wdata,
  output logic [31:0] cpu_mem_wstrb,

  output logic cpu_mem_ready,
  output logic [31:0] cpu_mem_rdata
);
  localparam integer MEM_SIZE = (1<<16);  // 16-bit address space
  localparam integer ADDR_WIDTH = $clog2(MEM_SIZE);

  // Memory outputs (CPU mem inputs)
  logic [2:0] cpu_mem_cycle;        // keep track of which byte we're reading/writing

  // Memory (for our own use)
  logic [ADDR_WIDTH-1:0] addra;
  logic [31:0] douta;
  logic [31:0] dina;
  logic wea;                        // write enable (port a)

  always_comb begin
    cpu_mem_ready = ~flash_active && (
      // If CPU wants to read/write, ready on 3rd or 4th cycle
      (cpu_mem_wstrb == 4'b0000) ?
        (cpu_mem_cycle == 3) :
        (cpu_mem_cycle == 4)
    );
    cpu_mem_rdata = douta;
  end

  always_ff @(posedge clk) begin
    logic [31:0] mask;                // 32-bit upsampled mask
  
    if (rst) begin
      cpu_mem_cycle <= 0;
      wea <= 1'b0;
      addra <= 0;
      
    end else begin
      if (cpu_mem_valid) begin
        /* States:
          0: prep request word
          1: wait (requesting word)
          2: wait
          3: receive word
        */

        case (cpu_mem_wstrb)
          // Read
          4'b0000: begin
            case (cpu_mem_cycle)
              0: begin
                addra <= cpu_mem_addr >> 2; // word address
                wea <= 1'b0;
              end
            endcase

            // Go to next read cycle
            cpu_mem_cycle <= (cpu_mem_cycle == 3) ? 0 : cpu_mem_cycle + 1;
          end
          
          // Write
          /* States:
            0: prep request word
            1: wait (requesting word)
            2: wait
            3: receive word, compute next word and request write
            4: done (reset wea to 0)
          */
          default: begin
            case (cpu_mem_cycle)
              0: begin
                addra <= cpu_mem_addr >> 2;
                wea <= 1'b0;
              end
              1: begin end
              2: begin end
              3: begin
                mask = {
                  {8{cpu_mem_wstrb[3]}},
                  {8{cpu_mem_wstrb[2]}},
                  {8{cpu_mem_wstrb[1]}},
                  {8{cpu_mem_wstrb[0]}}
                };
                dina <= (douta & (~mask)) | (cpu_mem_wdata & mask);
                wea <= 1'b1;
              end
              4: begin
                wea <= 1'b0;
              end
            endcase

            // Go to next read cycle
            cpu_mem_cycle <= (cpu_mem_cycle == 4) ? 0 : cpu_mem_cycle + 1;
          end
        endcase
      end
    end
  end

  // CPU
  picorv32 #(
    .REGS_INIT_ZERO(1),
    // 21-bit address space
    .STACKADDR(32'h1fffc),
    .CATCH_MISALIGN(0)
  ) cpu (
    .clk(clk),
    .resetn(~rst),

    // Memory interface
    // Outputs
    .mem_valid(cpu_mem_valid),
    .mem_instr(cpu_mem_instr),
    .mem_addr(cpu_mem_addr),
    .mem_wdata(cpu_mem_wdata),
    .mem_wstrb(cpu_mem_wstrb),

    // Inputs
    .mem_ready(cpu_mem_ready),
    .mem_rdata(cpu_mem_rdata),

    // Trap?
    .trap(trap)
  );

  // Memory
  xilinx_true_dual_port_read_first_2_clock_ram #(
    .RAM_WIDTH(32),
    .RAM_DEPTH(MEM_SIZE), // arbitrary memory width for now (21 bit address space)
    .RAM_PERFORMANCE("HIGH_PERFORMANCE"),
    .INIT_FILE(INIT_FILE)
  ) main_mem (
    // CPU read/write
    .addra(flash_active ? flash_addr : addra),
    .clka(clk),
    .wea(flash_active ? flash_wen : wea),
    .dina(flash_active ?  flash_data : dina),
    .ena(1'b1),
    .regcea(1'b1),
    .rsta(rst),
    .douta(douta),

    // HDMI read (frame buffer)
    .addrb(mmio_addr),
    .dinb(1'b0),
    .clkb(clk_mmio),
    .web(1'b0),
    .enb(1'b1),
    .rstb(rst),
    .regceb(1'b1),
    .doutb(mmio_rdata)
  );
  // ====================

endmodule

`default_nettype wire
