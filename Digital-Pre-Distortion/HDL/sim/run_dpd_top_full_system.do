if {![file exists simv2]} {
    file mkdir simv2
}

if {![file exists simv2/work/_info]} {
    vlib simv2/work
}

vlog -sv -work simv2/work -f rtl_v2/filelist.f tb/tb_dpd_top_full_system.sv
vsim -voptargs=+acc -lib simv2/work tb_dpd_top_full_system

add wave -divider "System Control"
add wave -radix binary sim:/tb_dpd_top_full_system/resetn
add wave -radix binary sim:/tb_dpd_top_full_system/sync_event
add wave -radix binary sim:/tb_dpd_top_full_system/dut/enable
add wave -radix binary sim:/tb_dpd_top_full_system/dut/force_bypass
add wave -radix binary sim:/tb_dpd_top_full_system/dpd_active
add wave -radix binary sim:/tb_dpd_top_full_system/dut/active_bank
add wave -radix binary sim:/tb_dpd_top_full_system/dut/coef_switch_pending
add wave -radix binary sim:/tb_dpd_top_full_system/dut/coef_switch_pulse
add wave -radix binary sim:/tb_dpd_top_full_system/irq
add wave -radix binary sim:/tb_dpd_top_full_system/train_request
add wave -radix hexadecimal sim:/tb_dpd_top_full_system/irq_status_rd

add wave -divider "Capture and Training"
add wave -radix binary sim:/tb_dpd_top_full_system/dut/capture_busy
add wave -radix binary sim:/tb_dpd_top_full_system/dut/capture_done
add wave -radix binary sim:/tb_dpd_top_full_system/dut/capture_lock
add wave -radix binary sim:/tb_dpd_top_full_system/dut/capture_ready
add wave -radix binary sim:/tb_dpd_top_full_system/dut/mac_train_busy
add wave -radix binary sim:/tb_dpd_top_full_system/dut/mac_train_done
add wave -radix binary sim:/tb_dpd_top_full_system/dut/mac_train_error
add wave -radix binary sim:/tb_dpd_top_full_system/dut/mac_coef_ready
add wave -radix unsigned sim:/tb_dpd_top_full_system/dut/trainer/epoch_count
add wave -radix unsigned sim:/tb_dpd_top_full_system/dut/trainer/term_idx
add wave -radix unsigned sim:/tb_dpd_top_full_system/dut/mac_error_acc
add wave -radix binary sim:/tb_dpd_top_full_system/dut/mac_coef_we
add wave -radix unsigned sim:/tb_dpd_top_full_system/dut/mac_coef_addr
add wave -radix decimal sim:/tb_dpd_top_full_system/dut/mac_coef_wdata

add wave -divider "Fast Path I/Q"
add wave -radix binary sim:/tb_dpd_top_full_system/sample_ready_out
add wave -radix binary sim:/tb_dpd_top_full_system/sample_valid_in
add wave -radix binary sim:/tb_dpd_top_full_system/sample_valid_out
add wave -radix decimal sim:/tb_dpd_top_full_system/sample_i_in
add wave -radix decimal sim:/tb_dpd_top_full_system/sample_q_in
add wave -radix decimal sim:/tb_dpd_top_full_system/sample_i_out
add wave -radix decimal sim:/tb_dpd_top_full_system/sample_q_out
add wave -radix unsigned sim:/tb_dpd_top_full_system/dut/gmp_coef_addr
add wave -radix binary sim:/tb_dpd_top_full_system/dut/mac_busy

add wave -divider "Feedback Alignment"
add wave -radix binary sim:/tb_dpd_top_full_system/feedback_valid_in
add wave -radix decimal sim:/tb_dpd_top_full_system/feedback_i_in
add wave -radix decimal sim:/tb_dpd_top_full_system/feedback_q_in
add wave -radix binary sim:/tb_dpd_top_full_system/dut/fb_valid_aligned
add wave -radix decimal sim:/tb_dpd_top_full_system/dut/fb_i_aligned
add wave -radix decimal sim:/tb_dpd_top_full_system/dut/fb_q_aligned

add wave -divider "Metrics"
add wave -radix unsigned sim:/tb_dpd_top_full_system/dut/metric_power
add wave -radix unsigned sim:/tb_dpd_top_full_system/dut/metric_error
add wave -radix unsigned sim:/tb_dpd_top_full_system/dut/metric_clipping
add wave -radix unsigned sim:/tb_dpd_top_full_system/dut/metric_drift
add wave -radix binary sim:/tb_dpd_top_full_system/dut/metrics_valid
add wave -radix binary sim:/tb_dpd_top_full_system/dut/metric_retrain_request

run -all
