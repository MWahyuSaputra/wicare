`timescale 1ns/1ps
module report_tx #(
  parameter integer REPORT_EVERY = 25
)(
  input               clk,
  input               rst,
  input               out_valid,
  input        [1:0]  status,
  input signed [31:0] mot,
  input signed [31:0] br,
  input               tx_busy,
  output reg          tx_start,
  output reg   [7:0]  tx_data
);
  reg [15:0] pkt;
  reg        sending;
  reg [4:0]  idx;
  reg [1:0]  s_l;
  reg [15:0] m_l, b_l;

  function [7:0] hexc(input [3:0] n);
    hexc = (n < 4'd10) ? (8'h30 + n) : (8'h41 + n - 4'd10);
  endfunction

  function [7:0] charat(input [4:0] k);
    case (k)
      5'd0:  charat = "S";
      5'd1:  charat = 8'h30 + s_l;
      5'd2:  charat = " ";
      5'd3:  charat = "M";
      5'd4:  charat = hexc(m_l[15:12]);
      5'd5:  charat = hexc(m_l[11:8]);
      5'd6:  charat = hexc(m_l[7:4]);
      5'd7:  charat = hexc(m_l[3:0]);
      5'd8:  charat = " ";
      5'd9:  charat = "B";
      5'd10: charat = hexc(b_l[15:12]);
      5'd11: charat = hexc(b_l[11:8]);
      5'd12: charat = hexc(b_l[7:4]);
      5'd13: charat = hexc(b_l[3:0]);
      5'd14: charat = 8'h0D;
      default: charat = 8'h0A;
    endcase
  endfunction

  always @(posedge clk) begin
    tx_start <= 1'b0;
    if (rst) begin
      pkt <= 0; sending <= 1'b0; idx <= 0;
    end else begin
      if (out_valid) begin
        if (pkt == REPORT_EVERY - 1) begin
          pkt <= 0;
          if (!sending) begin
            sending <= 1'b1; idx <= 0;
            s_l <= status;
            m_l <= (mot > 32'sd65535) ? 16'hFFFF : mot[15:0];
            b_l <= (br  > 32'sd65535) ? 16'hFFFF : br[15:0];
          end
        end else pkt <= pkt + 1'b1;
      end
      if (sending && !tx_busy && !tx_start) begin
        tx_data  <= charat(idx);
        tx_start <= 1'b1;
        if (idx == 5'd15) sending <= 1'b0; else idx <= idx + 1'b1;
      end
    end
  end
endmodule
