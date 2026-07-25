package require openlane

set design_name [expr {[info exists ::env(CHILD_DESIGN)] ? $::env(CHILD_DESIGN) : "dpd_soc_macro_top_100m"}]
set run_tag [expr {[info exists ::env(CHILD_TAG)] ? $::env(CHILD_TAG) : "macro_view_01"}]

prep -design ./designs/$design_name -tag $run_tag -overwrite

run_synthesis
run_floorplan
run_placement
run_cts

# This macro assembly netlist intentionally has no top-level signal routing yet.
# Generate physical views directly from the placed macro/floorplan database.
run_magic
run_klayout
save_state
exit
