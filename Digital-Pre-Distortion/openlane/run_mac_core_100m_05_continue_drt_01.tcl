package require openlane

# Continue mac_core_100m_05 from its post-global-route checkpoint.
# The first detailed-routing pass left one met1 short between _043153_ and VPWR.
# Synthesis, floorplan, placement, CTS, resizers and global routing are reused.

set run_dir "/openlane/designs/dpd_mac_engine_100m/runs/mac_core_100m_05"
source "$run_dir/config.tcl"

set ::env(SCRIPTS_DIR) "/openlane/scripts"
set ::env(CURRENT_INDEX) "24"

set gr_def   "$run_dir/tmp/routing/20-global_1.def"
set gr_odb   "$run_dir/tmp/routing/20-global_1.odb"
set gr_guide "$run_dir/tmp/routing/20-global_1.guide"

foreach checkpoint [list $gr_def $gr_odb $gr_guide] {
    if {![file exists $checkpoint]} {
        puts stderr "Missing post-global-route checkpoint: $checkpoint"
        exit 1
    }
}

set_def $gr_def
set_odb $gr_odb
set_guide $gr_guide

set ::env(CURRENT_NETLIST) "$run_dir/tmp/routing/global.nl.v"
set ::env(CURRENT_POWERED_NETLIST) "$run_dir/tmp/routing/global.pnl.v"
set ::env(CURRENT_SDC) "$run_dir/tmp/16-mac_engine.sdc"

set ::env(ROUTING_CORES) "1"
set ::env(DRT_OPT_ITERS) "24"
set ::env(RUN_FILL_INSERTION) "0"

detailed_routing
check_wire_lengths

set ::env(RUN_FILL_INSERTION) "1"
ins_fill_cells

run_magic
run_magic_spice_export
run_magic_drc
run_lvs
run_klayout
save_state
exit
