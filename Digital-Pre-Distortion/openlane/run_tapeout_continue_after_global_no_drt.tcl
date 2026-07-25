package require openlane

set design_name [expr {[info exists ::env(CHILD_DESIGN)] ? $::env(CHILD_DESIGN) : "dpd_soc_tapeout_top_100m"}]
set run_tag [expr {[info exists ::env(CHILD_TAG)] ? $::env(CHILD_TAG) : "tapeout_full_03"}]
set run_dir "/openlane/designs/$design_name/runs/$run_tag"

if {![file exists "$run_dir/config.tcl"]} {
    puts stderr "Missing run config: $run_dir/config.tcl"
    exit 1
}

source "$run_dir/config.tcl"
set ::env(SCRIPTS_DIR) "/openlane/scripts"
set ::env(CURRENT_INDEX) "18"
set ::env(RUN_DRT) "0"

set grt_def "$run_dir/tmp/routing/15-global.def"
set grt_odb "$run_dir/tmp/routing/15-global.odb"
set grt_nl "$run_dir/tmp/routing/global.nl.v"
set grt_pnl "$run_dir/tmp/routing/global.pnl.v"
set cts_sdc "$run_dir/results/cts/$::env(DESIGN_NAME).sdc"

foreach required [list $grt_def $grt_odb $grt_nl $grt_pnl $cts_sdc] {
    if {![file exists $required]} {
        puts stderr "Missing checkpoint artifact: $required"
        exit 1
    }
}

set_def $grt_def
set_odb $grt_odb
set ::env(CURRENT_NETLIST) $grt_nl
set ::env(CURRENT_POWERED_NETLIST) $grt_pnl
set ::env(CURRENT_SDC) $cts_sdc

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
