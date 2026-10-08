`timescale 1ns/1ps
module wicare_top #(
  parameter integer CLK_HZ         = 50_000_000,
  parameter integer BAUD           = 115200,
  parameter integer CLKS_PER_BIT   = CLK_HZ / BAUD,
  parameter integer LED_ACTIVE_LOW = 1,
  parameter integer REPORT_EVERY   = 25
)(
  input        clk,
  input        rst_n,
  input        uart_rx_pin,
  output       uart_tx_pin,
  output [3:0] led
);
  reg [7:0] por = 8'd0;
  reg       k1 = 1'b1, k2 = 1'b1;
  always @(posedge clk) begin
    k1 <= rst_n; k2 <= k1;
    if (por != 8'hFF) por <= por + 1'b1;
  end
  wire rst = (por != 8'hFF) | ~k2;

  wire [7:0] rx_byte;
  wire       rx_valid;
  uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
    .clk(clk), .rst(rst), .rx(uart_rx_pin), .data(rx_byte), .valid(rx_valid));

  wire              csi_valid;
  wire signed [7:0] csi_i, csi_q;
  wire [15:0]       ok_cnt, err_cnt;
  csi_frame_rx u_frame (
    .clk(clk), .rst(rst), .b(rx_byte), .bv(rx_valid),
    .csi_valid(csi_valid), .csi_i(csi_i), .csi_q(csi_q),
    .ok_cnt(ok_cnt), .err_cnt(err_cnt));

  wire [1:0]         status;
  wire               out_valid;
  wire signed [31:0] mot, br;
  wicare_lite u_core (
    .clk(clk), .rst(rst), .csi_valid(csi_valid),
    .csi_i(csi_i), .csi_q(csi_q),
    .status(status), .out_valid(out_valid), .mot(mot), .br(br));

  wire       tx_start, tx_busy;
  wire [7:0] tx_data;
  report_tx #(.REPORT_EVERY(REPORT_EVERY)) u_rep (
    .clk(clk), .rst(rst), .out_valid(out_valid), .status(status),
    .mot(mot), .br(br), .tx_busy(tx_busy), .tx_start(tx_start), .tx_data(tx_data));

  uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
    .clk(clk), .rst(rst), .start(tx_start), .data(tx_data),
    .tx(uart_tx_pin), .busy(tx_busy));

  reg blink;
  reg [4:0] bc;
  always @(posedge clk) begin
    if (rst) begin blink <= 1'b0; bc <= 0; end
    else if (out_valid) begin
      if (bc == 5'd24) begin bc <= 0; blink <= ~blink; end
      else bc <= bc + 1'b1;
    end
  end

  wire [3:0] led_on = {blink, status == 2'd2, status == 2'd1, status == 2'd0};
  assign led = LED_ACTIVE_LOW ? ~led_on : led_on;

endmodule
