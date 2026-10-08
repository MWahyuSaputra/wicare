`timescale 1ns/1ps
module tb_wicare;

  localparam integer N    = 6000;
  localparam integer FS   = 50;
  localparam integer SEG  = 1500;
  localparam integer SKIP = 250;

  reg clk = 0, rst = 1, csi_valid = 0;
  reg signed [7:0] csi_i = 0, csi_q = 0;
  wire [1:0] status;
  wire out_valid;
  wire signed [31:0] mot, br;

  wicare_lite dut (.clk(clk), .rst(rst), .csi_valid(csi_valid),
                 .csi_i(csi_i), .csi_q(csi_q), .status(status),
                 .out_valid(out_valid), .mot(mot), .br(br));

  always #10 clk = ~clk;

  reg [15:0] csi_mem    [0:N-1];
  reg [3:0]  golden_mem [0:N-1];
  reg [3:0]  label_mem  [0:N-1];

  integer k, mismatch, ok, nilai;
  integer ok_seg [0:3];
  integer n_seg  [0:3];
  reg [1:0] status_prev;

  initial begin
    $readmemh("csi_data.hex",      csi_mem);
    $readmemh("golden_status.hex", golden_mem);
    $readmemh("label.hex",         label_mem);
    mismatch = 0; status_prev = 0;
    for (k = 0; k < 4; k = k + 1) begin ok_seg[k] = 0; n_seg[k] = 0; end

    repeat (3) @(posedge clk);
    rst = 0;

    for (k = 0; k < N; k = k + 1) begin
      @(negedge clk);
      csi_i = csi_mem[k][15:8];
      csi_q = csi_mem[k][7:0];
      csi_valid = 1;
      @(negedge clk);
      csi_valid = 0;

      if (status !== golden_mem[k][1:0]) begin
        if (mismatch < 10)
          $display("MISMATCH paket %0d: RTL=%0d golden=%0d", k, status, golden_mem[k]);
        mismatch = mismatch + 1;
      end

      if (status != status_prev)
        $display("t = %0d.%02d s : status %0d -> %0d (%s)", k / FS, (k % FS) * 2,
                 status_prev, status,
                 status == 0 ? "KOSONG" : status == 1 ? "ORANG DIAM" : "ORANG BERGERAK");
      status_prev = status;

      if ((k % SEG) >= SKIP) begin
        n_seg[k / SEG] = n_seg[k / SEG] + 1;
        if (status == label_mem[k][1:0]) ok_seg[k / SEG] = ok_seg[k / SEG] + 1;
      end

      repeat (2) @(posedge clk);
    end

    $display("--------------------------------------------------");
    $display("Akurasi skenario 0 (kosong)   : %0d%%", 100 * ok_seg[0] / n_seg[0]);
    $display("Akurasi skenario 1 (diam)     : %0d%%", 100 * ok_seg[1] / n_seg[1]);
    $display("Akurasi skenario 2 (bergerak) : %0d%%", 100 * ok_seg[2] / n_seg[2]);
    $display("Akurasi skenario 3 (kosong)   : %0d%%", 100 * ok_seg[3] / n_seg[3]);
    if (mismatch == 0)
      $display("HASIL: PASS - RTL identik dengan golden model (%0d paket)", N);
    else
      $display("HASIL: FAIL - %0d paket berbeda dari golden model", mismatch);
    $display("--------------------------------------------------");
    $stop;
  end

endmodule
