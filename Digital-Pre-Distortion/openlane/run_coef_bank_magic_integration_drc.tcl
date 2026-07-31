package require openlane

prep -design ./designs/dpd_coef_bank_macro_100m \
    -tag coef_bank_magic_integration_drc_04

set ::env(CURRENT_GDS) /openlane/designs/dpd_coef_bank_macro_100m/runs/coef_bank_signoff_100m_04/results/signoff/coef_bank_macro.sram_blackbox.gds
set ::env(MAGIC_DRC_USE_GDS) 1
set ::env(QUIT_ON_MAGIC_DRC) 1
run_magic_drc
