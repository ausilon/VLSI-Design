package require openlane

# Re-hardening of MACcore after the capture RAM read boundary became registered.
# The RTL golden test includes the two explicit read-wait cycles.

set design_name "dpd_mac_engine_100m"
set run_tag [expr {[info exists ::env(CHILD_TAG)] ? $::env(CHILD_TAG) : "mac_core_100m_05"}]

prep -design ./designs/$design_name -tag $run_tag -overwrite

set ::env(CLOCK_PERIOD) "10.00"
set ::env(SYNTH_STRATEGY) "AREA 3"
set ::env(MAX_FANOUT_CONSTRAINT) "4"

set ::env(FP_CORE_UTIL) "15"
set ::env(PL_TARGET_DENSITY) "0.24"
set ::env(GRT_ADJUSTMENT) "0.20"

set ::env(PL_RESIZER_SETUP_MAX_BUFFER_PERCENT) "80"
set ::env(GLB_RESIZER_SETUP_MAX_BUFFER_PERCENT) "80"
set ::env(PL_RESIZER_SETUP_SLACK_MARGIN) "0.15"
set ::env(GLB_RESIZER_SETUP_SLACK_MARGIN) "0.12"
set ::env(PL_RESIZER_MAX_WIRE_LENGTH) "300"
set ::env(GLB_RESIZER_MAX_WIRE_LENGTH) "300"

set ::env(CTS_SINK_CLUSTERING_SIZE) "12"
set ::env(CTS_SINK_CLUSTERING_MAX_DIAMETER) "35"
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
