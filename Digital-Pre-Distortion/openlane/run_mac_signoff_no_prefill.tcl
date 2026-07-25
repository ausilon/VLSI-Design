package require openlane

set design_name "dpd_mac_engine_100m"
set run_tag [expr {[info exists ::env(CHILD_TAG)] ? $::env(CHILD_TAG) : "signoff_100m_no_prefill_01"}]

prep -design ./designs/$design_name -tag $run_tag -overwrite

run_synthesis
run_floorplan
run_placement
run_cts

# Keep the normal pre-route optimizations, then avoid filler before TritonRoute.
run_resizer_design_routing
run_resizer_timing_routing

if { [info exists ::env(DIODE_CELL)] && ($::env(DIODE_CELL) ne "") } {
    if { $::env(DIODE_ON_PORTS) ne "none" } {
        io_diode_insertion
    }
    if { $::env(RUN_HEURISTIC_DIODE_INSERTION) } {
        heuristic_diode_insertion
    }
}

add_route_obs
global_routing

if { $::env(RUN_DRT) } {
    detailed_routing
}

check_wire_lengths

# Insert fillers only after detailed routing to reduce peak DRT memory.
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
