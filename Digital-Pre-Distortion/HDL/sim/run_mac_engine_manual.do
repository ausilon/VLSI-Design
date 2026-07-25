if {![file exists simv2]} {
    file mkdir simv2
}

if {![file exists simv2/work/_info]} {
    vlib simv2/work
}

vlog -sv -work simv2/work -f rtl_v2/filelist.f tb/tb_mac_engine_manual.sv
vsim -voptargs=+acc -lib simv2/work tb_mac_engine_manual

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
