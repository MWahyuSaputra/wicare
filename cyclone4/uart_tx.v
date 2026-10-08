`timescale 1ns/1ps
module uart_tx #(
  parameter integer CLKS_PER_BIT = 434
)(
  input        clk,
  input        rst,
  input        start,
  input  [7:0] data,
  output reg   tx,
  output       busy
);
  reg [9:0]  sh;
  reg [15:0] cnt;
  reg [3:0]  bitn;
  reg        act;
  assign busy = act;

  always @(posedge clk) begin
    if (rst) begin
      tx <= 1'b1; act <= 1'b0;
    end else if (!act) begin
      tx <= 1'b1;
      if (start) begin
        sh <= {1'b1, data, 1'b0};
        act <= 1'b1; cnt <= 0; bitn <= 0;
      end
    end else begin
      tx <= sh[0];
      if (cnt == CLKS_PER_BIT - 1) begin
        cnt <= 0;
        sh  <= {1'b1, sh[9:1]};
        if (bitn == 4'd9) act <= 1'b0; else bitn <= bitn + 1'b1;
      end else cnt <= cnt + 1'b1;
    end
  end
endmodule
