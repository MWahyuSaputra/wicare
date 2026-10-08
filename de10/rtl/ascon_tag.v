`timescale 1ns/1ps
module ascon_tag (
  input              clk,
  input              rst,
  input              start,
  input      [63:0]  k0, k1,
  input      [63:0]  n0, n1,
  input      [63:0]  ad0, ad1,
  output reg         busy,
  output reg         done,
  output reg [63:0]  tag0, tag1
);
  localparam [63:0] IV = 64'h00001000808C0001;
  localparam IDLE = 2'd0, P_INIT = 2'd1, P_AD = 2'd2, P_FIN = 2'd3;

  reg [1:0]   st;
  reg [3:0]   idx;
  reg [319:0] s;

  function [63:0] rotr(input [63:0] x, input integer n);
    rotr = (x >> n) | (x << (64 - n));
  endfunction

  function [319:0] round(input [319:0] si, input [7:0] c);
    reg [63:0] x0, x1, x2, x3, x4, t0, t1, t2, t3, t4;
    begin
      {x0, x1, x2, x3, x4} = si;
      x2 = x2 ^ {56'd0, c};
      x0 = x0 ^ x4;  x4 = x4 ^ x3;  x2 = x2 ^ x1;
      t0 = ~x0 & x1; t1 = ~x1 & x2; t2 = ~x2 & x3; t3 = ~x3 & x4; t4 = ~x4 & x0;
      x0 = x0 ^ t1;  x1 = x1 ^ t2;  x2 = x2 ^ t3;  x3 = x3 ^ t4;  x4 = x4 ^ t0;
      x1 = x1 ^ x0;  x0 = x0 ^ x4;  x3 = x3 ^ x2;  x2 = ~x2;
      x0 = x0 ^ rotr(x0, 19) ^ rotr(x0, 28);
      x1 = x1 ^ rotr(x1, 61) ^ rotr(x1, 39);
      x2 = x2 ^ rotr(x2, 1)  ^ rotr(x2, 6);
      x3 = x3 ^ rotr(x3, 10) ^ rotr(x3, 17);
      x4 = x4 ^ rotr(x4, 7)  ^ rotr(x4, 41);
      round = {x0, x1, x2, x3, x4};
    end
  endfunction

  wire [7:0]   rc = 8'hF0 - idx * 8'h0F;
  wire [319:0] r  = round(s, rc);
  wire [63:0]  r0 = r[319:256], r1 = r[255:192], r2 = r[191:128],
               r3 = r[127:64],  r4 = r[63:0];

  always @(posedge clk) begin
    done <= 1'b0;
    if (rst) begin
      st <= IDLE; busy <= 1'b0; idx <= 0; s <= 0;
    end else case (st)
      IDLE: if (start) begin
              s <= {IV, k0, k1, n0, n1};
              idx <= 0; busy <= 1'b1; st <= P_INIT;
            end
      P_INIT: if (idx == 4'd11) begin
                s <= {r0 ^ ad0, r1 ^ ad1, r2, r3 ^ k0, r4 ^ k1};
                idx <= 4'd4; st <= P_AD;
              end else begin s <= r; idx <= idx + 1'b1; end
      P_AD:   if (idx == 4'd11) begin
                s <= {r0 ^ 64'h1, r1, r2 ^ k0, r3 ^ k1, r4 ^ 64'h8000000000000000};
                idx <= 0; st <= P_FIN;
              end else begin s <= r; idx <= idx + 1'b1; end
      P_FIN:  if (idx == 4'd11) begin
                tag0 <= r3 ^ k0; tag1 <= r4 ^ k1;
                done <= 1'b1; busy <= 1'b0; st <= IDLE;
              end else begin s <= r; idx <= idx + 1'b1; end
    endcase
  end
endmodule
