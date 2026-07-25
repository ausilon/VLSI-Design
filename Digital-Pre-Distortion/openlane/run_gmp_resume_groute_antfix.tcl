# Resume only the failed GMP global-routing step from the saved step-16 checkpoint.
# Run inside the OpenLane container from /openlane.

set run_dir "/openlane/designs/dpd_gmp_engine_100m/runs/signoff_100m_01"

source "$run_dir/config.tcl"

set ::env(SCRIPTS_DIR) "/openlane/scripts"
set ::env(CURRENT_DEF) "$run_dir/tmp/16-gmp_engine_ol_wrapper.def"
set ::env(CURRENT_ODB) "$run_dir/tmp/16-gmp_engine_ol_wrapper.odb"
set ::env(CURRENT_NETLIST) "$run_dir/tmp/16-gmp_engine_ol_wrapper.nl.v"
set ::env(CURRENT_POWERED_NETLIST) "$run_dir/tmp/16-gmp_engine_ol_wrapper.pnl.v"
set ::env(CURRENT_SDC) "$run_dir/tmp/16-gmp_engine_ol_wrapper.sdc"

set ::env(GRT_CONGESTION_REPORT_FILE) "$run_dir/tmp/routing/groute-antfix-congestion.rpt"
set ::env(SAVE_DEF) "$run_dir/tmp/routing/18-global-antfix.def"
set ::env(SAVE_ODB) "$run_dir/tmp/routing/18-global-antfix.odb"
set ::env(SAVE_GUIDE) "$run_dir/tmp/routing/18-global-antfix.guide"

# The previous full run reached overflow 0 and then died during antenna repair.
# Keep repair enabled, but reduce the iterative repair load.
set ::env(GRT_REPAIR_ANTENNAS) "1"
set ::env(GRT_ANT_ITERS) "8"
set ::env(GRT_ANT_MARGIN) "10"
set ::env(DIODE_PADDING) "2"

source "$::env(SCRIPTS_DIR)/openroad/groute.tcl"
