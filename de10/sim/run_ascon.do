vlib work
vlog ../rtl/ascon_tag.v tb_ascon.v
vsim -voptargs=+acc work.tb_ascon
run -all
