`timescale 1ns/1ps
module tb_ascon;
  localparam integer NV = 200;
  reg clk = 0, rst = 1, start = 0;
  reg [63:0] k0, k1, n0, n1, ad0, ad1;
  wire busy, done;
  wire [63:0] tag0, tag1;
  ascon_tag dut (.clk(clk), .rst(rst), .start(start), .k0(k0), .k1(k1),
                 .n0(n0), .n1(n1), .ad0(ad0), .ad1(ad1),
                 .busy(busy), .done(done), .tag0(tag0), .tag1(tag1));
  always #10 clk = ~clk;
  reg [63:0] v [0:NV*8-1];
  integer i, err;
  initial begin
    $readmemh("ascon_vectors.hex", v);
    err = 0;
    repeat (2) @(posedge clk); rst = 0;
    for (i = 0; i < NV; i = i + 1) begin
      @(negedge clk);
      k0 = v[i*8]; k1 = v[i*8+1]; n0 = v[i*8+2]; n1 = v[i*8+3];
      ad0 = v[i*8+4]; ad1 = v[i*8+5]; start = 1;
      @(negedge clk); start = 0;
      wait (done); @(negedge clk);
      if (tag0 !== v[i*8+6] || tag1 !== v[i*8+7]) begin
        if (err < 5) $display("SALAH vektor %0d: %h %h", i, tag0, tag1);
        err = err + 1;
      end
    end
    if (err == 0) $display("ASCON: PASS %0d/%0d vektor identik dengan referensi", NV, NV);
    else          $display("ASCON: FAIL %0d vektor salah", err);
    $stop;
  end
endmodule
