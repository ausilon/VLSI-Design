onerror {quit -code 1 -f}

set RUN_DIR [file normalize [pwd]]
if {[file isdirectory [file join $RUN_DIR Digital-Pre-Distortion HDL]]} {
    set DPD_ROOT [file join $RUN_DIR Digital-Pre-Distortion]
} elseif {[file isdirectory [file join $RUN_DIR HDL]]} {
    set DPD_ROOT $RUN_DIR
} else {
    error "run from the VLSI-Design repository root or Digital-Pre-Distortion"
}
set DESIGN_DIR [file join $DPD_ROOT openlane dpd_gmp_engine_100m]
set DATASET_DIR [file join $DPD_ROOT datasets opendpd_coeffs]
set WORK_DIR /tmp/dpd_gmp_openlane_regression_work

if {[file exists $WORK_DIR]} {
    file delete -force $WORK_DIR
}
vlib $WORK_DIR

vlog -sv -work $WORK_DIR \
    [file join $DESIGN_DIR src isqrt32_pipe.v] \
    [file join $DESIGN_DIR src gmp_mac_lane.v] \
    [file join $DESIGN_DIR src gmp_engine.v] \
    [file join $DESIGN_DIR tb tb_gmp_engine_opendpd_openlane.sv]

vsim -c -lib $WORK_DIR tb_gmp_engine_opendpd_openlane \
    +COEF_HEX=[file join $DATASET_DIR coef_bank_openDPD.hex] \
    +SAMPLES_HEX=[file join $DATASET_DIR gmp_opendpd_full_samples_iq_q15.hex] \
    +EXPECTED_HEX=[file join $DATASET_DIR gmp_opendpd_full_expected_iq_q15.hex]

run -all
quit -code 0 -f
