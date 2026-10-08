create_clock -name clk -period 20.000 [get_ports clk]
derive_clock_uncertainty
set_false_path -from [get_ports {rst_n uart_rx_pin}]
set_false_path -to   [get_ports {uart_tx_pin led[*]}]
