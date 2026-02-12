// Main memory
// Implemented in SRAM for now
// May be tied to SD card ROM in the future

// tbh i have no idea how this works but we need it for whatever reason
`ifdef SYNTHESIS
  `define FPATH(X) `"X`"
`else /* ! SYNTHESIS */
  `define FPATH(X) `"../data/X`"
`endif  /* ! SYNTHESIS */

module main_memory (
  input wire clk,
  input wire rst,     // doesn't really do anything but nice to hook up perhaps

  input Word addra,
  input Word dina,
  input wire w_ena,
  input wire r_ena,

  input Word addrb,
  input Word dinb,
  input wire w_enb,
  input wire r_enb,

  output Word douta,
  output logic dout_valida,

  output Word doutb,
  output logic dout_validb
);
  // TWO-CYCLE DELAY!
  
  logic [31:0] addra_prev;
  logic [31:0] addrb_prev;
  
  always_ff @(posedge clk) begin
    addra_prev <= addra;
    addrb_prev <= addrb;
    
    // Mildly inefficient but works if assume two-cycle delay
    dout_valida <= (addra_prev == addra);
    dout_validb <= (addrb_prev == addrb);
  end
  
  xilinx_single_port_ram_read_first #(
    .RAM_WIDTH(32),
    .RAM_DEPTH(1024*4), // 128 kb
    .RAM_PERFORMANCE("HIGH_PERFORMANCE"),
    .INIT_FILE(`FPATH(prog.mem))
  ) main_mem (
    // PORT A
    .addra(addra),
    .dina(dina),
    .clka(clk),
    .wea(w_ena),
    .ena(1'b1),
    .rsta(rst),
    .regcea(1'b1),
    .douta(douta),

    // PORT B
    .addrb(addrb),
    .dinb(dinb),
    .web(w_enb),
    .enb(1'b1),
    .rstb(rst),
    .regceb(1'b1),
    .doutb(doutb)
  );
endmodule
