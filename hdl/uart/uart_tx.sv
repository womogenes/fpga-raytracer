`timescale 1ns / 1ps
`default_nettype none

// Minimal UART transmitter used by the UberDDR3 controller's optional debug UART.
//
// Interface matches the instance in `hdl/dram/ddr3_controller.sv`.
module uart_tx #(
  parameter int unsigned BIT_RATE = 9600,
  parameter int unsigned CLK_HZ = 100_000_000,
  parameter int unsigned PAYLOAD_BITS = 8,
  parameter int unsigned STOP_BITS = 1
) (
  input  wire                   clk,
  input  wire                   resetn,       // active-low reset
  output logic                  uart_txd,
  output logic                  uart_tx_busy,
  input  wire                   uart_tx_en,
  input  wire [PAYLOAD_BITS-1:0] uart_tx_data
);

  localparam int unsigned CLKS_PER_BIT = (CLK_HZ + BIT_RATE/2) / BIT_RATE;
  localparam int unsigned CTR_W = (CLKS_PER_BIT <= 1) ? 1 : $clog2(CLKS_PER_BIT);

  typedef enum logic [1:0] {
    ST_IDLE  = 2'd0,
    ST_START = 2'd1,
    ST_DATA  = 2'd2,
    ST_STOP  = 2'd3
  } tx_state_t;

  tx_state_t state;

  logic [CTR_W-1:0] bit_ctr;
  logic [$clog2(PAYLOAD_BITS+1)-1:0] data_idx;
  logic [$clog2(STOP_BITS+1)-1:0] stop_idx;
  logic [PAYLOAD_BITS-1:0] shreg;

  wire bit_tick = (CLKS_PER_BIT == 1) ? 1'b1 : (bit_ctr == (CLKS_PER_BIT-1));

  always_ff @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      uart_txd <= 1'b1;
      uart_tx_busy <= 1'b0;
      state <= ST_IDLE;
      bit_ctr <= '0;
      data_idx <= '0;
      stop_idx <= '0;
      shreg <= '0;
    end else begin
      // default: count clocks within a UART bit when active
      if (state != ST_IDLE) begin
        if (bit_tick) bit_ctr <= '0;
        else bit_ctr <= bit_ctr + 1'b1;
      end else begin
        bit_ctr <= '0;
      end

      case (state)
        ST_IDLE: begin
          uart_txd <= 1'b1;
          uart_tx_busy <= 1'b0;
          data_idx <= '0;
          stop_idx <= '0;
          if (uart_tx_en) begin
            shreg <= uart_tx_data;
            uart_tx_busy <= 1'b1;
            uart_txd <= 1'b0; // start bit
            state <= ST_START;
          end
        end

        ST_START: begin
          if (bit_tick) begin
            uart_txd <= shreg[0];
            shreg <= {1'b0, shreg[PAYLOAD_BITS-1:1]};
            data_idx <= 1;
            state <= ST_DATA;
          end
        end

        ST_DATA: begin
          if (bit_tick) begin
            if (data_idx == PAYLOAD_BITS) begin
              uart_txd <= 1'b1; // stop bit(s)
              stop_idx <= 0;
              state <= ST_STOP;
            end else begin
              uart_txd <= shreg[0];
              shreg <= {1'b0, shreg[PAYLOAD_BITS-1:1]};
              data_idx <= data_idx + 1'b1;
            end
          end
        end

        ST_STOP: begin
          if (bit_tick) begin
            if (stop_idx == STOP_BITS-1) begin
              state <= ST_IDLE;
            end else begin
              stop_idx <= stop_idx + 1'b1;
              uart_txd <= 1'b1;
            end
          end
        end
      endcase
    end
  end

endmodule

`default_nettype wire

