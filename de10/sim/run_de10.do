vlib work
vlog ../rtl/uart_rx.v ../rtl/csi_frame_rx.v ../rtl/wicare_pipe.v ../rtl/ascon_tag.v \
     ../rtl/key_prov.v ../rtl/wicare_avalon.v tb_de10.v
vsim -voptargs=+acc work.tb_de10
add wave -divider "AVALON (HPS)"
add wave -radix hex /tb_de10/addr /tb_de10/wr /tb_de10/rd /tb_de10/rdata /tb_de10/irq
add wave -divider "PIPELINE"
add wave -format analog-step -height 70 -min 0 -max 1500 -radix decimal /tb_de10/dut/mot
add wave -format analog-step -height 70 -min 0 -max 900  -radix decimal /tb_de10/dut/br
add wave -format analog-step -height 50 -min 0 -max 2 -radix unsigned /tb_de10/dut/status
add wave -divider "LAPORAN + ASCON"
add wave -radix unsigned /tb_de10/dut/key_valid /tb_de10/dut/r_cnt /tb_de10/dut/a_busy
add wave -radix hex /tb_de10/dut/t0_l /tb_de10/dut/t1_l
run -all
wave zoom full
