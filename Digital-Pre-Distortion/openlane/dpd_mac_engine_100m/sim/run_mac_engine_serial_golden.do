transcript on
if {[file exists work]} {
  vdel -lib work -all
}
vlib work
vmap work work

vlog -sv src/mac_engine.v tb/tb_mac_engine_serial_golden.sv
vsim -voptargs=+acc work.tb_mac_engine_serial_golden

add wave -divider clocks_control
add wave sim:/tb_mac_engine_serial_golden/clk
add wave sim:/tb_mac_engine_serial_golden/resetn
add wave sim:/tb_mac_engine_serial_golden/train_start
add wave sim:/tb_mac_engine_serial_golden/capture_done
add wave sim:/tb_mac_engine_serial_golden/train_busy
add wave sim:/tb_mac_engine_serial_golden/train_done
add wave sim:/tb_mac_engine_serial_golden/train_error
add wave sim:/tb_mac_engine_serial_golden/coef_ready
add wave sim:/tb_mac_engine_serial_golden/capture_lock
add wave sim:/tb_mac_engine_serial_golden/capture_release

add wave -divider mac_read
add wave -radix unsigned sim:/tb_mac_engine_serial_golden/mac_rd_en
add wave -radix unsigned sim:/tb_mac_engine_serial_golden/mac_rd_addr
add wave -radix hexadecimal sim:/tb_mac_engine_serial_golden/mac_rd_data

add wave -divider trainer_state
add wave -radix unsigned sim:/tb_mac_engine_serial_golden/dut/state
add wave -radix unsigned sim:/tb_mac_engine_serial_golden/dut/epoch_count
add wave -radix unsigned sim:/tb_mac_engine_serial_golden/dut/sample_count
add wave -radix unsigned sim:/tb_mac_engine_serial_golden/dut/term_idx
add wave -radix decimal sim:/tb_mac_engine_serial_golden/dut/epoch_model_error_acc
add wave -radix decimal sim:/tb_mac_engine_serial_golden/dut/best_model_error_acc

add wave -divider term2_golden_checkpoint
add wave -radix decimal sim:/tb_mac_engine_serial_golden/dut/acc_num_real(2)
add wave -radix decimal sim:/tb_mac_engine_serial_golden/dut/acc_num_imag(2)
add wave -radix decimal sim:/tb_mac_engine_serial_golden/dut/acc_den(2)

add wave -divider coef_write
add wave -radix unsigned sim:/tb_mac_engine_serial_golden/coef_we
add wave -radix unsigned sim:/tb_mac_engine_serial_golden/coef_addr
add wave -radix decimal sim:/tb_mac_engine_serial_golden/coef_wdata
add wave -radix decimal sim:/tb_mac_engine_serial_golden/status_error_acc

run -all
