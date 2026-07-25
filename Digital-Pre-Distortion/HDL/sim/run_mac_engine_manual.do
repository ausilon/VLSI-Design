if {![file exists sim]} {
    file mkdir sim
}

if {![file exists sim/work/_info]} {
    vlib sim/work
}

vlog -sv -work sim/work -f rtl/filelist.f tb/tb_mac_engine_manual.sv
vsim -voptargs=+acc -lib sim/work tb_mac_engine_manual

add wave -divider "MACcore Control"
add wave -radix binary sim:/tb_mac_engine_manual/resetn
add wave -radix binary sim:/tb_mac_engine_manual/train_start
add wave -radix binary sim:/tb_mac_engine_manual/capture_done
add wave -radix binary sim:/tb_mac_engine_manual/capture_lock
add wave -radix binary sim:/tb_mac_engine_manual/capture_release
add wave -radix binary sim:/tb_mac_engine_manual/train_busy
add wave -radix binary sim:/tb_mac_engine_manual/train_done
add wave -radix binary sim:/tb_mac_engine_manual/train_error
add wave -radix binary sim:/tb_mac_engine_manual/coef_ready

add wave -divider "Capture Read"
add wave -radix binary sim:/tb_mac_engine_manual/mac_rd_en
add wave -radix unsigned sim:/tb_mac_engine_manual/mac_rd_addr
add wave -radix hexadecimal sim:/tb_mac_engine_manual/mac_rd_data

add wave -divider "Coefficient Write"
add wave -radix binary sim:/tb_mac_engine_manual/coef_we
add wave -radix unsigned sim:/tb_mac_engine_manual/coef_addr
add wave -radix decimal sim:/tb_mac_engine_manual/coef_wdata
add wave -radix unsigned sim:/tb_mac_engine_manual/status_error_acc

run -all
