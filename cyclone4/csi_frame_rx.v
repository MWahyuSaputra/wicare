`timescale 1ns/1ps
module csi_frame_rx (
  input                   clk,
  input                   rst,
  input       [7:0]       b,
  input                   bv,
  output reg              csi_valid,
  output reg signed [7:0] csi_i,
  output reg signed [7:0] csi_q,
  output reg [15:0]       ok_cnt,
  output reg [15:0]       err_cnt
);
  localparam S_AA = 3'd0, S_55 = 3'd1, S_I = 3'd2, S_Q = 3'd3, S_CHK = 3'd4;
  reg [2:0] st;
  reg [7:0] ti, tq;

  always @(posedge clk) begin
    csi_valid <= 1'b0;
    if (rst) begin
      st <= S_AA; ok_cnt <= 0; err_cnt <= 0;
    end else if (bv) begin
      case (st)
        S_AA:  st <= (b == 8'hAA) ? S_55 : S_AA;
        S_55:  st <= (b == 8'h55) ? S_I : (b == 8'hAA) ? S_55 : S_AA;
        S_I:   begin ti <= b; st <= S_Q; end
        S_Q:   begin tq <= b; st <= S_CHK; end
        S_CHK: begin
                 st <= S_AA;
                 if (b == (ti ^ tq)) begin
                   csi_i <= ti; csi_q <= tq; csi_valid <= 1'b1;
                   ok_cnt <= ok_cnt + 1'b1;
                 end else
                   err_cnt <= err_cnt + 1'b1;
               end
        default: st <= S_AA;
      endcase
    end
  end
endmodule
