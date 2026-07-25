# Continue GMP signoff after a successful run_gmp_resume_groute_antfix.tcl.
# Run inside the OpenLane container from /openlane.

package require openlane

set run_dir "/openlane/designs/dpd_gmp_engine_100m/runs/signoff_100m_01"
source "$run_dir/config.tcl"

set ::env(SCRIPTS_DIR) "/openlane/scripts"
set ::env(CURRENT_INDEX) "18"

set antfix_def "$run_dir/tmp/routing/18-global-antfix.def"
set antfix_odb "$run_dir/tmp/routing/18-global-antfix.odb"
set antfix_guide "$run_dir/tmp/routing/18-global-antfix.guide"

if {![file exists $antfix_def] || ![file exists $antfix_odb] || ![file exists $antfix_guide]} {
    puts stderr "Missing antfix checkpoint. Run run_gmp_resume_groute_antfix.tcl first."
    exit 1
}

set_def $antfix_def
set_odb $antfix_odb
set_guide $antfix_guide

write_verilog \
    "$run_dir/tmp/routing/18-global-antfix.nl.v" \
    -powered_to "$run_dir/tmp/routing/18-global-antfix.pnl.v" \
    -indexed_log "$run_dir/logs/routing/18-global-antfix-write-netlist.log"

if { $::env(RUN_FILL_INSERTION) } {
    ins_fill_cells
}

if { $::env(RUN_DRT) } {
    detailed_routing
}

check_wire_lengths

run_magic
run_magic_spice_export
run_magic_drc
run_lvs
run_klayout
save_state
exit
