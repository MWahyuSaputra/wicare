`timescale 1ns/1ps
module key_prov #(
  parameter integer CLKS_PER_BIT = 434
)(
  input              clk,
  input              rst,
  input              prov_rx,
  output reg         key_valid,
  output     [63:0]  k0,
  output     [63:0]  k1
);
  wire [7:0] b;
  wire       bv;
  uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
    .clk(clk), .rst(rst), .rx(prov_rx), .data(b), .valid(bv));

  reg [127:0] key;
  reg         active;
  reg [4:0]   n;
  assign k0 = key[63:0];
  assign k1 = key[127:64];

  always @(posedge clk) begin
    if (rst) begin
      key <= 128'd0; key_valid <= 1'b0; active <= 1'b0; n <= 0;
    end else if (bv && !key_valid) begin
      if (!active) begin
        if (b == 8'h4B) begin active <= 1'b1; n <= 0; end
      end else begin
        key <= {b, key[127:8]};
        if (n == 5'd15) begin key_valid <= 1'b1; active <= 1'b0; end
        else n <= n + 1'b1;
      end
    end
  end
endmodule
