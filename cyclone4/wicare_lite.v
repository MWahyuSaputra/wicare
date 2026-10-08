`timescale 1ns/1ps
module wicare_lite #(
  parameter integer T_MOT = 250,
  parameter integer T_BR  = 100,
  parameter integer HOLD  = 25
)(
  input                    clk,
  input                    rst,
  input                    csi_valid,
  input  signed [7:0]      csi_i,
  input  signed [7:0]      csi_q,
  output reg    [1:0]      status,
  output reg               out_valid,
  output reg signed [31:0] mot,
  output reg signed [31:0] br
);

  reg signed [31:0] s_fast, s_slow;
  reg               first;
  reg         [1:0] cand_prev;
  reg         [7:0] cnt;

  wire signed [31:0] pwr = csi_i * csi_i + csi_q * csi_q;
  wire signed [31:0] x8  = pwr <<< 8;

  wire signed [31:0] sf_cur = first ? x8 : s_fast;
  wire signed [31:0] ss_cur = first ? x8 : s_slow;

  wire signed [31:0] sf_new = sf_cur + ((x8 - sf_cur) >>> 3);
  wire signed [31:0] ss_new = ss_cur + ((x8 - ss_cur) >>> 8);
  wire signed [31:0] y_fast = sf_new >>> 8;
  wire signed [31:0] y_slow = ss_new >>> 8;

  wire signed [31:0] hp     = pwr - y_fast;
  wire signed [31:0] bp     = y_fast - y_slow;
  wire signed [31:0] hp_abs = (hp < 0) ? -hp : hp;
  wire signed [31:0] bp_abs = (bp < 0) ? -bp : bp;
  wire signed [31:0] mot_new = mot + ((hp_abs - mot) >>> 4);
  wire signed [31:0] br_new  = br  + ((bp_abs - br)  >>> 6);

  wire [1:0] cand = (mot_new > T_MOT) ? 2'd2 :
                    (br_new  > T_BR ) ? 2'd1 : 2'd0;

  wire [7:0] cnt_new = (cand != cand_prev) ? 8'd0 :
                       (cnt < HOLD)        ? cnt + 8'd1 : cnt;

  always @(posedge clk) begin
    if (rst) begin
      s_fast <= 0;  s_slow <= 0;  mot <= 0;  br <= 0;
      first <= 1'b1;  cand_prev <= 2'd0;  cnt <= 8'd0;
      status <= 2'd0;  out_valid <= 1'b0;
    end else begin
      out_valid <= csi_valid;
      if (csi_valid) begin
        first     <= 1'b0;
        s_fast    <= sf_new;
        s_slow    <= ss_new;
        mot       <= mot_new;
        br        <= br_new;
        cand_prev <= cand;
        cnt       <= cnt_new;
        if (cnt_new == HOLD) status <= cand;
      end
    end
  end

endmodule
