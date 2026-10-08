package require -exact qsys 16.1

set_module_property NAME wicare
set_module_property VERSION 1.0
set_module_property DISPLAY_NAME "Wi-CARE"
set_module_property DESCRIPTION "Deteksi kehadiran CSI WiFi + laporan bertanda Ascon-AEAD128"
set_module_property GROUP "WICARE"
set_module_property AUTHOR "Tim Wi-CARE POLINES"
set_module_property EDITABLE true
set_module_property INTERNAL false

add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL wicare_avalon
add_fileset_file wicare_avalon.v  VERILOG PATH rtl/wicare_avalon.v TOP_LEVEL_FILE
add_fileset_file wicare_pipe.v    VERILOG PATH rtl/wicare_pipe.v
add_fileset_file ascon_tag.v    VERILOG PATH rtl/ascon_tag.v
add_fileset_file key_prov.v     VERILOG PATH rtl/key_prov.v
add_fileset_file uart_rx.v      VERILOG PATH rtl/uart_rx.v
add_fileset_file csi_frame_rx.v VERILOG PATH rtl/csi_frame_rx.v

add_parameter CLKS_PER_BIT INTEGER 434
set_parameter_property CLKS_PER_BIT DISPLAY_NAME "Clock per bit UART (clk/baud)"
set_parameter_property CLKS_PER_BIT HDL_PARAMETER true

add_interface clock clock end
add_interface_port clock clk clk Input 1

add_interface reset reset end
set_interface_property reset associatedClock clock
set_interface_property reset synchronousEdges DEASSERT
add_interface_port reset reset reset Input 1

add_interface s0 avalon end
set_interface_property s0 addressUnits WORDS
set_interface_property s0 associatedClock clock
set_interface_property s0 associatedReset reset
set_interface_property s0 readLatency 1
set_interface_property s0 readWaitTime 0
set_interface_property s0 writeWaitTime 0
set_interface_property s0 maximumPendingReadTransactions 0
set_interface_property s0 explicitAddressSpan 0
add_interface_port s0 avs_s0_address   address   Input  6
add_interface_port s0 avs_s0_read      read      Input  1
add_interface_port s0 avs_s0_readdata  readdata  Output 32
add_interface_port s0 avs_s0_write     write     Input  1
add_interface_port s0 avs_s0_writedata writedata Input  32

add_interface irq0 interrupt end
set_interface_property irq0 associatedAddressablePoint s0
set_interface_property irq0 associatedClock clock
set_interface_property irq0 associatedReset reset
add_interface_port irq0 ins_irq0_irq irq Output 1

add_interface pins conduit end
set_interface_property pins associatedClock clock
add_interface_port pins coe_csi_rx  csi_rx  Input  1
add_interface_port pins coe_prov_rx prov_rx Input  1
add_interface_port pins coe_led     led     Output 4
