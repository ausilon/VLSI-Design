package require openlane

# GMP macro run for the feature-pipelined + lane-pipelined version.
#
# Functional status before physical run:
#   - tb_gmp_engine_opendpd PASS in Questa
#   - 64 OpenDPD golden outputs matched bit-exactly
#   - gmp_engine_ol_wrapper compiles with 0 warnings
#
# Timing target:
#   - CLOCK_PERIOD = 10.00 ns ~= 100 MHz
#   - II = 4 cycles/sample
#   - Throughput target ~= 25 MSps
#
# This run supersedes gmp_lane_piped_100m_01. That previous run still failed
# setup because the feature precompute path kept mag_q15/isqrt and powers in
# one registered path.

set design_name "dpd_gmp_engine_100m"
set run_tag [expr {[info exists ::env(CHILD_TAG)] ? $::env(CHILD_TAG) : "gmp_feature_piped_100m_01"}]

prep -design ./designs/$design_name -tag $run_tag -overwrite

set ::env(CLOCK_PERIOD) "10.00"
set ::env(SYNTH_STRATEGY) "AREA 3"
set ::env(MAX_FANOUT_CONSTRAINT) "4"

set ::env(FP_CORE_UTIL) "20"
set ::env(PL_TARGET_DENSITY) "0.32"

set ::env(PL_RESIZER_SETUP_MAX_BUFFER_PERCENT) "80"
set ::env(GLB_RESIZER_SETUP_MAX_BUFFER_PERCENT) "80"
set ::env(PL_RESIZER_SETUP_SLACK_MARGIN) "0.15"
set ::env(GLB_RESIZER_SETUP_SLACK_MARGIN) "0.12"
set ::env(PL_RESIZER_MAX_WIRE_LENGTH) "250"
set ::env(GLB_RESIZER_MAX_WIRE_LENGTH) "250"

set ::env(CTS_SINK_CLUSTERING_SIZE) "12"
set ::env(CTS_SINK_CLUSTERING_MAX_DIAMETER) "30"
set ::env(CTS_REPORT_TIMING) "1"

set ::env(ROUTING_CORES) "1"
set ::env(DRT_OPT_ITERS) "12"
set ::env(RUN_FILL_INSERTION) "0"

run_synthesis
run_floorplan
run_placement
run_cts
run_routing

set ::env(RUN_FILL_INSERTION) "1"
ins_fill_cells

run_magic
run_magic_spice_export
run_magic_drc
run_lvs
run_klayout
save_state
exit
