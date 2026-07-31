transcript on
if {[file exists work]} {
  vdel -lib work -all
}
vlib work
vmap work work

vlog -sv tb/sky130_sram_models.sv \
  src/capture_ram_macro.v \
  tb/tb_capture_ram_macro_sync.sv
vsim -voptargs=+acc work.tb_capture_ram_macro_sync
run -all
