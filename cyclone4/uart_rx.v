`timescale 1ns/1ps
module uart_rx #(
  parameter integer CLKS_PER_BIT = 434
)(
  input            clk,
  input            rst,
  input            rx,
  output reg [7:0] data,
  output reg       valid
);
  reg rx1 = 1'b1, rx2 = 1'b1;
  always @(posedge clk) begin rx1 <= rx; rx2 <= rx1; end

  localparam IDLE = 2'd0, START = 2'd1, DATA = 2'd2, STOP = 2'd3;
  reg [1:0]  st;
  reg [15:0] cnt;
  reg [2:0]  bitn;
  reg [7:0]  sh;

  always @(posedge clk) begin
    valid <= 1'b0;
    if (rst) begin
      st <= IDLE; cnt <= 0; bitn <= 0;
    end else case (st)
      IDLE:  if (!rx2) begin st <= START; cnt <= 0; end
      START: if (cnt == CLKS_PER_BIT/2 - 1) begin
               cnt <= 0; bitn <= 0;
               st  <= rx2 ? IDLE : DATA;
             end else cnt <= cnt + 1'b1;
      DATA:  if (cnt == CLKS_PER_BIT - 1) begin
               cnt <= 0;
               sh  <= {rx2, sh[7:1]};
               if (bitn == 3'd7) st <= STOP; else bitn <= bitn + 1'b1;
             end else cnt <= cnt + 1'b1;
      STOP:  if (cnt == CLKS_PER_BIT - 1) begin
               st <= IDLE;
               if (rx2) begin data <= sh; valid <= 1'b1; end
             end else cnt <= cnt + 1'b1;
    endcase
  end
endmodule
