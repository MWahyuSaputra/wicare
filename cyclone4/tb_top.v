`timescale 1ns/1ps
module tb_top;

  localparam integer N   = 6000;
  localparam integer CPB = 8;

  reg  clk = 0, rst_n = 1, esp_tx = 1;
  wire fpga_tx;
  wire [3:0] led;

  wicare_top #(.CLKS_PER_BIT(CPB), .REPORT_EVERY(250)) dut (
    .clk(clk), .rst_n(rst_n), .uart_rx_pin(esp_tx),
    .uart_tx_pin(fpga_tx), .led(led));

  always #10 clk = ~clk;

  reg [15:0] csi_mem    [0:N-1];
  reg [3:0]  golden_mem [0:N-1];

  task send_byte(input [7:0] b);
    integer j;
    begin
      esp_tx = 0;                       repeat (CPB) @(posedge clk);
      for (j = 0; j < 8; j = j + 1) begin
        esp_tx = b[j];                  repeat (CPB) @(posedge clk);
      end
      esp_tx = 1;                       repeat (CPB) @(posedge clk);
    end
  endtask

  task send_frame(input [7:0] i, input [7:0] q, input [7:0] chk);
    begin
      send_byte(8'hAA); send_byte(8'h55);
      send_byte(i); send_byte(q); send_byte(chk);
    end
  endtask

  integer j2;
  reg [7:0] c;
  initial forever begin
    @(negedge fpga_tx);
    repeat (CPB / 2) @(posedge clk);
    for (j2 = 0; j2 < 8; j2 = j2 + 1) begin
      repeat (CPB) @(posedge clk);
      c[j2] = fpga_tx;
    end
    repeat (CPB) @(posedge clk);
    if (c != 8'h0D) $write("%c", c);
  end

  integer k, mismatch;
  initial begin
    $readmemh("csi_data.hex",      csi_mem);
    $readmemh("golden_status.hex", golden_mem);
    mismatch = 0;
    repeat (300) @(posedge clk);

    send_byte(8'h12); send_byte(8'h34);
    send_frame(8'h10, 8'h20, 8'h00);

    $display("Laporan dari FPGA (tiap 250 paket = 5 detik):");
    for (k = 0; k < N; k = k + 1) begin
      send_frame(csi_mem[k][15:8], csi_mem[k][7:0],
                 csi_mem[k][15:8] ^ csi_mem[k][7:0]);
      repeat (4) @(posedge clk);
      if (dut.u_core.status !== golden_mem[k][1:0]) begin
        if (mismatch < 10)
          $display("MISMATCH paket %0d: RTL=%0d golden=%0d",
                   k, dut.u_core.status, golden_mem[k]);
        mismatch = mismatch + 1;
      end
      repeat (20) @(posedge clk);
    end
    repeat (2000) @(posedge clk);

    $display("--------------------------------------------------");
    $display("Frame diterima : %0d (harus %0d)", dut.ok_cnt, N);
    $display("Frame ditolak  : %0d (harus 1)", dut.err_cnt);
    if (mismatch == 0 && dut.ok_cnt == N && dut.err_cnt == 1)
      $display("HASIL: PASS - jalur UART + core identik dengan golden model");
    else
      $display("HASIL: FAIL - mismatch %0d", mismatch);
    $display("--------------------------------------------------");
    $stop;
  end

endmodule
