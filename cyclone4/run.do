vlib work
vlog wicare_lite.v tb_wicare.v
vsim -voptargs=+acc work.tb_wicare

add wave -divider "INPUT CSI (dari ESP32)"
add wave -format analog-step -height 60 -min -128 -max 127 -radix decimal /tb_wicare/csi_i
add wave -divider "DAYA KANAL"
add wave -format analog-step -height 80 -min 0 -max 10000 -radix decimal /tb_wicare/dut/pwr
add wave -divider "FITUR"
add wave -format analog-step -height 80 -min 0 -max 1500 -radix decimal /tb_wicare/dut/mot
add wave -format analog-step -height 80 -min 0 -max 900  -radix decimal /tb_wicare/dut/br
add wave -divider "HASIL (0 kosong, 1 diam, 2 bergerak)"
add wave -format analog-step -height 60 -min 0 -max 2 -radix unsigned /tb_wicare/status

run -all
wave zoom full
