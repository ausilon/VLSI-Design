package require openlane

set design_name [expr {[info exists ::env(CHILD_DESIGN)] ? $::env(CHILD_DESIGN) : "dpd_soc_tapeout_top_100m"}]
set run_tag [expr {[info exists ::env(CHILD_TAG)] ? $::env(CHILD_TAG) : "tapeout_full_01"}]

prep -design ./designs/$design_name -tag $run_tag -overwrite

run_synthesis
run_floorplan
run_placement
run_cts

# This top-level assembly is currently a macro scaffold: the hard macros are
# present, but most functional inter-macro signal nets are not connected yet.
# OpenROAD's routing resizers fail on this shape because global routing has
# zero routed signal nets. Keep them disabled until the production top netlist
# is connected.

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

# DRT requires routing guides. In the current macro scaffold the top has zero
# routed signal nets, so TritonRoute receives zero guides and exits with an
# internal range-check error. Re-enable DRT when the production top netlist has
# real inter-macro connectivity.
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
