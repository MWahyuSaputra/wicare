set_location_assignment PIN_23 -to clk
set_location_assignment PIN_25 -to rst_n

set_location_assignment PIN_87 -to led[0]
set_location_assignment PIN_86 -to led[1]
set_location_assignment PIN_85 -to led[2]
set_location_assignment PIN_84 -to led[3]

set_location_assignment PIN_XX -to uart_rx_pin
set_location_assignment PIN_YY -to uart_tx_pin

set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to clk
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to rst_n
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to led[*]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to uart_rx_pin
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to uart_tx_pin
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to uart_rx_pin
