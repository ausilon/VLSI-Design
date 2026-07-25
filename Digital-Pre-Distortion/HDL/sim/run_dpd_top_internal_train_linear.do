if {![file exists sim]} {
    file mkdir sim
}

if {![file exists sim/work/_info]} {
    vlib sim/work
}

vlog -sv -work sim/work -f rtl/filelist.f tb/tb_dpd_top_internal_train_linear.sv
vsim -voptargs=+acc -lib sim/work tb_dpd_top_internal_train_linear

add wave -divider "Top Control"
add wave -radix binary sim:/tb_dpd_top_internal_train_linear/resetn
add wave -radix binary sim:/tb_dpd_top_internal_train_linear/sync_event
add wave -radix binary sim:/tb_dpd_top_internal_train_linear/dut/enable
add wave -radix binary sim:/tb_dpd_top_internal_train_linear/dut/force_bypass
add wave -radix binary sim:/tb_dpd_top_internal_train_linear/dpd_active
add wave -radix binary sim:/tb_dpd_top_internal_train_linear/dut/active_bank
add wave -radix binary sim:/tb_dpd_top_internal_train_linear/dut/coef_switch_pending
add wave -radix binary sim:/tb_dpd_top_internal_train_linear/dut/coef_switch_pulse
add wave -radix binary sim:/tb_dpd_top_internal_train_linear/irq
add wave -radix binary sim:/tb_dpd_top_internal_train_linear/train_request
add wave -radix binary sim:/tb_dpd_top_internal_train_linear/dut/capture_done
add wave -radix binary sim:/tb_dpd_top_internal_train_linear/dut/mac_train_busy
add wave -radix binary sim:/tb_dpd_top_internal_train_linear/dut/mac_train_done
add wave -radix binary sim:/tb_dpd_top_internal_train_linear/dut/mac_train_error
add wave -radix binary sim:/tb_dpd_top_internal_train_linear/dut/mac_coef_ready
add wave -radix binary sim:/tb_dpd_top_internal_train_linear/dut/mac_busy

add wave -divider "Fast Path Bypass/DPD"
add wave -radix binary sim:/tb_dpd_top_internal_train_linear/sample_ready_out
add wave -radix binary sim:/tb_dpd_top_internal_train_linear/sample_ready_in
add wave -radix binary sim:/tb_dpd_top_internal_train_linear/sample_valid_in
add wave -radix binary sim:/tb_dpd_top_internal_train_linear/sample_valid_out
add wave -radix decimal sim:/tb_dpd_top_internal_train_linear/sample_i_in
add wave -radix decimal sim:/tb_dpd_top_internal_train_linear/sample_q_in
add wave -radix decimal sim:/tb_dpd_top_internal_train_linear/sample_i_out
add wave -radix decimal sim:/tb_dpd_top_internal_train_linear/sample_q_out
add wave -radix unsigned sim:/tb_dpd_top_internal_train_linear/dut/gmp_coef_addr

add wave -divider "Capture Alignment"
add wave -radix binary sim:/tb_dpd_top_internal_train_linear/sample_valid_in
add wave -radix decimal sim:/tb_dpd_top_internal_train_linear/sample_i_in
add wave -radix decimal sim:/tb_dpd_top_internal_train_linear/sample_q_in
add wave -radix binary sim:/tb_dpd_top_internal_train_linear/feedback_valid_in
add wave -radix decimal sim:/tb_dpd_top_internal_train_linear/feedback_i_in
add wave -radix decimal sim:/tb_dpd_top_internal_train_linear/feedback_q_in
add wave -radix decimal sim:/tb_dpd_top_internal_train_linear/dut/fb_i_aligned
add wave -radix decimal sim:/tb_dpd_top_internal_train_linear/dut/fb_q_aligned
add wave -radix binary sim:/tb_dpd_top_internal_train_linear/dut/fb_valid_aligned

add wave -divider "MACcore NLMS Full 39-Term GMP Coefficients"
add wave -radix binary sim:/tb_dpd_top_internal_train_linear/dut/mac_coef_we
add wave -radix unsigned sim:/tb_dpd_top_internal_train_linear/dut/mac_coef_addr
add wave -radix decimal sim:/tb_dpd_top_internal_train_linear/dut/mac_coef_wdata
add wave -radix unsigned sim:/tb_dpd_top_internal_train_linear/dut/mac_error_acc

run -all
