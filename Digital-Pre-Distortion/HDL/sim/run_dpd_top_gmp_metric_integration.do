if {![file exists sim]} {
    file mkdir sim
}

if {![file exists sim/work/_info]} {
    vlib sim/work
}

vlog -sv -work sim/work -f rtl/filelist.f tb/tb_dpd_top_gmp_metric_integration.sv
vsim -voptargs=+acc -lib sim/work tb_dpd_top_gmp_metric_integration

add wave -divider "DPD Top Control"
add wave -radix binary sim:/tb_dpd_top_gmp_metric_integration/resetn
add wave -radix binary sim:/tb_dpd_top_gmp_metric_integration/sync_event
add wave -radix binary sim:/tb_dpd_top_gmp_metric_integration/dpd_active
add wave -radix binary sim:/tb_dpd_top_gmp_metric_integration/sample_ready_out
add wave -radix binary sim:/tb_dpd_top_gmp_metric_integration/sample_valid_in
add wave -radix binary sim:/tb_dpd_top_gmp_metric_integration/sample_valid_out
add wave -radix binary sim:/tb_dpd_top_gmp_metric_integration/irq
add wave -radix binary sim:/tb_dpd_top_gmp_metric_integration/train_request

add wave -divider "I/Q Datapath"
add wave -radix decimal sim:/tb_dpd_top_gmp_metric_integration/sample_i_in
add wave -radix decimal sim:/tb_dpd_top_gmp_metric_integration/sample_q_in
add wave -radix decimal sim:/tb_dpd_top_gmp_metric_integration/sample_i_out
add wave -radix decimal sim:/tb_dpd_top_gmp_metric_integration/sample_q_out
add wave -radix decimal sim:/tb_dpd_top_gmp_metric_integration/exp_i
add wave -radix decimal sim:/tb_dpd_top_gmp_metric_integration/exp_q

add wave -divider "Metrics"
add wave -radix unsigned sim:/tb_dpd_top_gmp_metric_integration/metric_power_rd
add wave -radix unsigned sim:/tb_dpd_top_gmp_metric_integration/metric_error_rd
add wave -radix unsigned sim:/tb_dpd_top_gmp_metric_integration/metric_clip_rd
add wave -radix unsigned sim:/tb_dpd_top_gmp_metric_integration/metric_drift_rd
add wave -radix hexadecimal sim:/tb_dpd_top_gmp_metric_integration/irq_status_rd

run -all
