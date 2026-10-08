`timescale 1ns/1ps
module tb_de10;
  localparam integer N   = 6000;
  localparam integer NB  = 500;
  localparam integer CPB = 8;

  reg clk = 0, reset = 1;
  reg  [5:0]  addr = 0;
  reg         rd = 0, wr = 0;
  reg  [31:0] wdata = 0;
  wire [31:0] rdata;
  wire        irq;
  reg         csi_rx = 1, prov_rx = 1;
  wire [3:0]  led;

  wicare_avalon #(.CLKS_PER_BIT(CPB)) dut (
    .clk(clk), .reset(reset),
    .avs_s0_address(addr), .avs_s0_read(rd), .avs_s0_readdata(rdata),
    .avs_s0_write(wr), .avs_s0_writedata(wdata),
    .ins_irq0_irq(irq), .coe_csi_rx(csi_rx), .coe_prov_rx(prov_rx), .coe_led(led));

  always #10 clk = ~clk;

  task av_write(input [7:0] off, input [31:0] d);
    begin
      @(negedge clk); addr = off[7:2]; wdata = d; wr = 1;
      @(negedge clk); wr = 0;
    end
  endtask
  task av_read(input [7:0] off, output [31:0] d);
    begin
      @(negedge clk); addr = off[7:2]; rd = 1;
      @(negedge clk); rd = 0; d = rdata;
    end
  endtask

  task uart_byte(input sel, input [7:0] b);
    integer j;
    begin
      if (sel) prov_rx = 0; else csi_rx = 0;
      repeat (CPB) @(posedge clk);
      for (j = 0; j < 8; j = j + 1) begin
        if (sel) prov_rx = b[j]; else csi_rx = b[j];
        repeat (CPB) @(posedge clk);
      end
      if (sel) prov_rx = 1; else csi_rx = 1;
      repeat (CPB) @(posedge clk);
    end
  endtask
  task esp_frame(input [7:0] i, input [7:0] q);
    begin
      uart_byte(0, 8'hAA); uart_byte(0, 8'h55);
      uart_byte(0, i); uart_byte(0, q); uart_byte(0, i ^ q);
    end
  endtask

  integer fd, n_rep;
  reg [31:0] r_cnt, r_info, r_feat, r_thr, tg0, tg1, tg2, tg3, tmp;
  task service;
    begin
      if (irq) begin
        av_read(8'h30, r_cnt);  av_read(8'h34, r_info);
        av_read(8'h38, r_feat); av_read(8'h3C, r_thr);
        av_read(8'h40, tg0); av_read(8'h44, tg1); av_read(8'h48, tg2); av_read(8'h4C, tg3);
        av_write(8'h00, 32'h2);
        $fdisplay(fd, "%0d %0d %0d %0d %0d %0d %0d %0d %h%h%h%h",
                  r_cnt, r_info[7:0], r_info[15:8], r_info[23:16],
                  r_feat[15:0], r_feat[31:16], r_thr[15:0], r_thr[31:16],
                  tg3, tg2, tg1, tg0);
        n_rep = n_rep + 1;
      end
    end
  endtask

  reg [15:0] csi_mem [0:N-1];
  integer k, a;
  reg [31:0] st;

  initial begin
    $readmemh("csi_data.hex", csi_mem);
    fd = $fopen("reports.txt", "w");
    n_rep = 0;
    repeat (4) @(posedge clk); reset = 0;

    av_write(8'h0C, {7'd0, 1'b0, 16'd25, 8'd3});
    av_write(8'h10, 32'd250);
    av_write(8'h14, 32'd100);
    av_write(8'h18, 32'h55667788);
    av_write(8'h1C, 32'h11223344);
    for (k = 0; k < 50; k = k + 1) begin
      esp_frame(csi_mem[k][15:8], csi_mem[k][7:0]); service;
    end
    repeat (20) @(posedge clk);
    av_read(8'h50, tmp);
    $display("Fase 1: tanpa kunci -> laporan %0d (harus 0), terlewat %0d (harus 2)", n_rep, tmp);

    uart_byte(1, 8'h4B);
    for (k = 0; k < 16; k = k + 1) uart_byte(1, k);
    uart_byte(1, 8'h4B);
    for (k = 0; k < 16; k = k + 1) uart_byte(1, 8'hFF);
    av_read(8'h04, st);
    $display("Fase 2: key_valid = %0d (harus 1)", st[9]);

    av_write(8'h00, 32'h1);
    for (k = 0; k < N; k = k + 1) begin
      esp_frame(csi_mem[k][15:8], csi_mem[k][7:0]); service;
    end
    repeat (100) @(posedge clk); service;
    $display("Fase 3: laporan dari jalur ESP32 = %0d (harus 240)", n_rep);

    av_write(8'h0C, {7'd0, 1'b1, 16'd25, 8'd3});
    av_write(8'h00, 32'h1);
    for (k = 0; k < NB; k = k + 1) begin
      av_write(8'h08, {16'd0, csi_mem[k]});
      repeat (40) @(posedge clk); service;
    end
    $display("Fase 4: total laporan = %0d (harus 260)", n_rep);

    tmp = 0;
    for (a = 0; a < 64; a = a + 1) begin
      av_read(a * 4, st);
      if (st == 32'h03020100 || st == 32'h07060504 || st == 32'h0B0A0908 || st == 32'h0F0E0D0C)
        tmp = tmp + 1;
    end
    $display("Cek kebocoran kunci di 64 register: %0d kata kunci terlihat (harus 0)", tmp);
    av_read(8'h50, tmp);
    $display("Laporan terlewat total: %0d (harus 2, dari fase 1)", tmp);
    $fclose(fd);
    $display("Jalankan: python verify_reports.py");
    $stop;
  end
endmodule
