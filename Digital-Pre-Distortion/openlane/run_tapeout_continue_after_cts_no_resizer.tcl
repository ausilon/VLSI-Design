package require openlane

set design_name [expr {[info exists ::env(CHILD_DESIGN)] ? $::env(CHILD_DESIGN) : "dpd_soc_tapeout_top_100m"}]
set run_tag [expr {[info exists ::env(CHILD_TAG)] ? $::env(CHILD_TAG) : "tapeout_full_02"}]
set run_dir "/openlane/designs/$design_name/runs/$run_tag"

if {![file exists "$run_dir/config.tcl"]} {
    puts stderr "Missing run config: $run_dir/config.tcl"
    exit 1
}

source "$run_dir/config.tcl"
set ::env(SCRIPTS_DIR) "/openlane/scripts"
set ::env(CURRENT_INDEX) "15"

set cts_def "$run_dir/results/cts/$::env(DESIGN_NAME).def"
set cts_odb "$run_dir/results/cts/$::env(DESIGN_NAME).odb"
set cts_sdc "$run_dir/results/cts/$::env(DESIGN_NAME).sdc"
set pl_nl "$run_dir/results/placement/$::env(DESIGN_NAME).nl.v"
set pl_pnl "$run_dir/results/placement/$::env(DESIGN_NAME).pnl.v"

foreach required [list $cts_def $cts_odb $cts_sdc $pl_nl $pl_pnl] {
    if {![file exists $required]} {
        puts stderr "Missing checkpoint artifact: $required"
        exit 1
    }
}

set_def $cts_def
set_odb $cts_odb
set ::env(CURRENT_SDC) $cts_sdc
set ::env(CURRENT_NETLIST) $pl_nl
set ::env(CURRENT_POWERED_NETLIST) $pl_pnl
set ::env(GRT_REPAIR_ANTENNAS) "0"
set ::env(RUN_HEURISTIC_DIODE_INSERTION) "0"

if { [info exists ::env(DIODE_CELL)] && ($::env(DIODE_CELL) ne "") } {
    if { $::env(DIODE_ON_PORTS) ne "none" } {
        io_diode_insertion
    }
    if { [info exists ::env(RUN_HEURISTIC_DIODE_INSERTION)] && $::env(RUN_HEURISTIC_DIODE_INSERTION) } {
        heuristic_diode_insertion
    }
}

add_route_obs
global_routing

# See run_tapeout_full_no_prefill.tcl: this macro scaffold currently has zero
# signal routing guides.
if { $::env(RUN_DRT) } {
    detailed_routing
}

check_wire_lengths

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
