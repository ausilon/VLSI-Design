# Continue GMP signoff from 18-global-antfix, but skip filler insertion before DRT.
# This reduces TritonRoute memory pressure for the large GMP macro.
# Run inside the OpenLane container from /openlane.

package require openlane

set run_dir "/openlane/designs/dpd_gmp_engine_100m/runs/signoff_100m_01"
source "$run_dir/config.tcl"

set ::env(SCRIPTS_DIR) "/openlane/scripts"
set ::env(CURRENT_INDEX) "21"

set antfix_def "$run_dir/tmp/routing/18-global-antfix.def"
set antfix_odb "$run_dir/tmp/routing/18-global-antfix.odb"
set antfix_guide "$run_dir/tmp/routing/18-global-antfix.guide"
set antfix_nl "$run_dir/tmp/routing/18-global-antfix.nl.v"
set antfix_pnl "$run_dir/tmp/routing/18-global-antfix.pnl.v"

if {![file exists $antfix_def] || ![file exists $antfix_odb] || ![file exists $antfix_guide]} {
    puts stderr "Missing antfix checkpoint. Run run_gmp_resume_groute_antfix.tcl first."
    exit 1
}

set_def $antfix_def
set_odb $antfix_odb
set_guide $antfix_guide
set ::env(CURRENT_NETLIST) $antfix_nl
set ::env(CURRENT_POWERED_NETLIST) $antfix_pnl
set ::env(CURRENT_SDC) "$run_dir/tmp/16-gmp_engine_ol_wrapper.sdc"

# Lower peak memory during detailed route. Increase later only if DRT completes
# but leaves too many violations.
set ::env(ROUTING_CORES) "1"
set ::env(DRT_OPT_ITERS) "16"

if { $::env(RUN_DRT) } {
    detailed_routing
}

check_wire_lengths

# Insert filler after detailed routing to reduce DRT database size.
if { $::env(RUN_FILL_INSERTION) } {
    ins_fill_cells
}

run_magic
run_magic_spice_export
run_magic_drc
run_lvs
run_klayout
save_state
exit
