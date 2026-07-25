package require openlane

set design_name [expr {[info exists ::env(CHILD_DESIGN)] ? $::env(CHILD_DESIGN) : "dpd_soc_tapeout_top_100m"}]
set run_tag [expr {[info exists ::env(CHILD_TAG)] ? $::env(CHILD_TAG) : "tapeout_pdn_check_01"}]

prep -design ./designs/$design_name -tag $run_tag -overwrite
run_synthesis
run_floorplan
save_state
exit
