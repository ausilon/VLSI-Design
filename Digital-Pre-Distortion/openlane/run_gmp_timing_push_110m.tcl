package require openlane

# Timing-push run for the current OpenLane-derived GMP macro.
# Goal: keep the same HDL/floorplan style, but drive synthesis/placement/CTS
# harder than signoff_100m_01 to close above the 96 MHz minimum for 24 Msps
# with the current 4-cycle/sample GMP architecture.

set design_name "dpd_gmp_engine_100m"
set run_tag [expr {[info exists ::env(CHILD_TAG)] ? $::env(CHILD_TAG) : "timing_push_110m_01"}]

prep -design ./designs/$design_name -tag $run_tag -overwrite

# Target 100-110 MHz class timing. 9.0 ns corresponds to 111.1 MHz.
set ::env(CLOCK_PERIOD) "9.00"
set ::env(SYNTH_STRATEGY) "DELAY 2"
set ::env(MAX_FANOUT_CONSTRAINT) "4"

# Keep the same conservative area/floorplan envelope used by the previous GMP run.
set ::env(FP_CORE_UTIL) "25"
set ::env(PL_TARGET_DENSITY) "0.40"

# Push setup repair more aggressively without changing the HDL.
set ::env(PL_RESIZER_SETUP_MAX_BUFFER_PERCENT) "75"
set ::env(GLB_RESIZER_SETUP_MAX_BUFFER_PERCENT) "75"
set ::env(PL_RESIZER_SETUP_SLACK_MARGIN) "0.12"
set ::env(GLB_RESIZER_SETUP_SLACK_MARGIN) "0.08"
set ::env(PL_RESIZER_MAX_WIRE_LENGTH) "350"
set ::env(GLB_RESIZER_MAX_WIRE_LENGTH) "350"

# Slightly tighter clock clustering for the large datapath.
set ::env(CTS_SINK_CLUSTERING_SIZE) "16"
set ::env(CTS_SINK_CLUSTERING_MAX_DIAMETER) "35"
set ::env(CTS_REPORT_TIMING) "1"

# Keep routing memory under control. Filler is inserted manually after DRT.
set ::env(ROUTING_CORES) "1"
set ::env(DRT_OPT_ITERS) "16"
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
