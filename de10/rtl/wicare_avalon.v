`timescale 1ns/1ps
module wicare_avalon #(
  parameter integer CLKS_PER_BIT = 434
)(
  input             clk,
  input             reset,
  input      [5:0]  avs_s0_address,
  input             avs_s0_read,
  output reg [31:0] avs_s0_readdata,
  input             avs_s0_write,
  input      [31:0] avs_s0_writedata,
  output            ins_irq0_irq,
  input             coe_csi_rx,
  input             coe_prov_rx,
  output     [3:0]  coe_led
);
  reg [7:0]  room_id;
  reg [15:0] report_every;
  reg        src_hps;
  reg [15:0] t_mot, t_br;
  reg [63:0] session;
  reg        clr_pipe, clr_ready;
  reg        hps_csi_valid;
  reg [15:0] hps_csi;

  wire wr = avs_s0_write;
  always @(posedge clk) begin
    clr_pipe <= 1'b0; clr_ready <= 1'b0; hps_csi_valid <= 1'b0;
    if (reset) begin
      room_id <= 8'd1; report_every <= 16'd25; src_hps <= 1'b0;
      t_mot <= 16'd250; t_br <= 16'd100; session <= 64'd0;
    end else if (wr) case (avs_s0_address)
      6'd0: begin clr_pipe <= avs_s0_writedata[0]; clr_ready <= avs_s0_writedata[1]; end
      6'd2: begin hps_csi <= avs_s0_writedata[15:0]; hps_csi_valid <= 1'b1; end
      6'd3: begin room_id <= avs_s0_writedata[7:0];
                  report_every <= avs_s0_writedata[23:8];
                  src_hps <= avs_s0_writedata[24]; end
      6'd4: t_mot <= avs_s0_writedata[15:0];
      6'd5: t_br  <= avs_s0_writedata[15:0];
      6'd6: session[31:0]  <= avs_s0_writedata;
      6'd7: session[63:32] <= avs_s0_writedata;
      default: ;
    endcase
  end

  wire [7:0]        rx_b;
  wire              rx_bv;
  wire              g_valid;
  wire signed [7:0] g_i, g_q;
  wire [15:0]       csi_ok, csi_err;
  uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
    .clk(clk), .rst(reset), .rx(coe_csi_rx), .data(rx_b), .valid(rx_bv));
  csi_frame_rx u_frame (
    .clk(clk), .rst(reset), .b(rx_b), .bv(rx_bv),
    .csi_valid(g_valid), .csi_i(g_i), .csi_q(g_q),
    .ok_cnt(csi_ok), .err_cnt(csi_err));

  wire              p_valid = src_hps ? hps_csi_valid : g_valid;
  wire signed [7:0] p_i     = src_hps ? hps_csi[15:8] : g_i;
  wire signed [7:0] p_q     = src_hps ? hps_csi[7:0]  : g_q;

  wire [1:0]         status;
  wire               out_valid;
  wire signed [31:0] mot, br;
  wicare_pipe u_pipe (
    .clk(clk), .rst(reset), .clr(clr_pipe), .t_mot(t_mot), .t_br(t_br),
    .csi_valid(p_valid), .csi_i(p_i), .csi_q(p_q),
    .status(status), .out_valid(out_valid), .mot(mot), .br(br));

  wire        key_valid;
  wire [63:0] k0, k1;
  key_prov #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_key (
    .clk(clk), .rst(reset), .prov_rx(coe_prov_rx),
    .key_valid(key_valid), .k0(k0), .k1(k1));

  reg  [15:0] pkt;
  reg  [31:0] r_cnt;
  reg  [7:0]  r_room, r_flags;
  reg  [1:0]  r_status;
  reg  [15:0] r_mot, r_br, r_tmot, r_tbr;
  reg  [31:0] dropped;
  reg         r_ready;
  reg         a_start;
  wire        a_busy, a_done;
  wire [63:0] tag0, tag1;
  reg  [63:0] t0_l, t1_l;

  wire [15:0] every = (report_every == 16'd0) ? 16'd1 : report_every;
  wire [15:0] mot16 = (mot > 32'sd65535) ? 16'hFFFF : mot[15:0];
  wire [15:0] br16  = (br  > 32'sd65535) ? 16'hFFFF : br[15:0];

  wire [63:0] ad0 = {r_mot, 6'd0, r_status, r_cnt, r_room};
  wire [63:0] ad1 = {8'h01, r_flags, r_tbr, r_tmot, r_br};
  wire [63:0] n0  = session;
  wire [63:0] n1  = {24'd0, r_room, r_cnt};

  always @(posedge clk) begin
    a_start <= 1'b0;
    if (reset) begin
      pkt <= 0; r_cnt <= 0; r_ready <= 1'b0; dropped <= 0;
    end else begin
      if (clr_ready) r_ready <= 1'b0;
      if (clr_pipe)  pkt <= 0;
      else if (out_valid) begin
        if (pkt >= every - 1'b1) begin
          pkt <= 0;
          if (key_valid && !r_ready && !a_busy && !a_start) begin
            r_room <= room_id;  r_status <= status;
            r_mot  <= mot16;    r_br     <= br16;
            r_tmot <= t_mot;    r_tbr    <= t_br;
            r_flags <= {7'd0, src_hps};
            a_start <= 1'b1;
          end else
            dropped <= dropped + 1'b1;
        end else pkt <= pkt + 1'b1;
      end
      if (a_done) begin
        t0_l <= tag0; t1_l <= tag1;
        r_ready <= 1'b1;
      end
      if (a_done) r_cnt <= r_cnt + 1'b1;
    end
  end

  ascon_tag u_ascon (
    .clk(clk), .rst(reset), .start(a_start),
    .k0(k0), .k1(k1), .n0(n0), .n1(n1), .ad0(ad0), .ad1(ad1),
    .busy(a_busy), .done(a_done), .tag0(tag0), .tag1(tag1));

  assign ins_irq0_irq = r_ready;

  always @(posedge clk) begin
    if (avs_s0_read) case (avs_s0_address)
      6'd1:  avs_s0_readdata <= {16'h0100, 4'd0, src_hps, a_busy, key_valid, r_ready, 6'd0, status};
      6'd3:  avs_s0_readdata <= {7'd0, src_hps, report_every, room_id};
      6'd4:  avs_s0_readdata <= {16'd0, t_mot};
      6'd5:  avs_s0_readdata <= {16'd0, t_br};
      6'd6:  avs_s0_readdata <= session[31:0];
      6'd7:  avs_s0_readdata <= session[63:32];
      6'd8:  avs_s0_readdata <= mot;
      6'd9:  avs_s0_readdata <= br;
      6'd10: avs_s0_readdata <= {16'd0, csi_ok};
      6'd11: avs_s0_readdata <= {16'd0, csi_err};
      6'd12: avs_s0_readdata <= r_cnt - 1'b1;
      6'd13: avs_s0_readdata <= {8'd0, r_flags, 6'd0, r_status, r_room};
      6'd14: avs_s0_readdata <= {r_br, r_mot};
      6'd15: avs_s0_readdata <= {r_tbr, r_tmot};
      6'd16: avs_s0_readdata <= t0_l[31:0];
      6'd17: avs_s0_readdata <= t0_l[63:32];
      6'd18: avs_s0_readdata <= t1_l[31:0];
      6'd19: avs_s0_readdata <= t1_l[63:32];
      6'd20: avs_s0_readdata <= dropped;
      default: avs_s0_readdata <= 32'd0;
    endcase
  end

  assign coe_led = {key_valid, status == 2'd2, status == 2'd1, status == 2'd0};

endmodule
