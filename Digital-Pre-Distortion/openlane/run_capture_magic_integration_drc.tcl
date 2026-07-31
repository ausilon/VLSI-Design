package require openlane

prep -design ./designs/dpd_capture_ram_macro_100m \
    -tag capture_ram_magic_integration_drc_04

set ::env(CURRENT_GDS) /openlane/designs/dpd_capture_ram_macro_100m/runs/capture_ram_signoff_100m_13/results/signoff/capture_ram_macro.sram_blackbox.gds
set ::env(MAGIC_DRC_USE_GDS) 1
set ::env(QUIT_ON_MAGIC_DRC) 1
run_magic_drc
