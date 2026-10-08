vlib work
vlog uart_rx.v uart_tx.v csi_frame_rx.v report_tx.v wicare_lite.v wicare_top.v tb_top.v
vsim -voptargs=+acc work.tb_top

add wave -divider "UART"
add wave /tb_top/esp_tx /tb_top/fpga_tx
add wave -divider "FRAME"
add wave -radix decimal /tb_top/dut/csi_i /tb_top/dut/csi_q
add wave -radix unsigned /tb_top/dut/ok_cnt /tb_top/dut/err_cnt
add wave -divider "CORE"
add wave -format analog-step -height 80 -min 0 -max 1500 -radix decimal /tb_top/dut/mot
add wave -format analog-step -height 80 -min 0 -max 900  -radix decimal /tb_top/dut/br
add wave -format analog-step -height 60 -min 0 -max 2 -radix unsigned /tb_top/dut/status
add wave -divider "LED (aktif low)"
add wave -radix binary /tb_top/led

run -all
wave zoom full
