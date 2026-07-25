package require openlane

if {![info exists ::env(CHILD_DESIGN)]} {
    puts stderr "CHILD_DESIGN is required, for example: dpd_metrics_100m"
    exit 1
}

set design_name $::env(CHILD_DESIGN)
set run_tag [expr {[info exists ::env(CHILD_TAG)] ? $::env(CHILD_TAG) : "floorplan_100m_01"}]

prep -design ./designs/$design_name -tag $run_tag -overwrite
run_synthesis
run_floorplan
save_state
exit
