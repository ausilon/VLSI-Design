package require openlane

prep -design ./designs/dpd_capture_ram_macro_100m \
    -tag capture_ram_klayout_drc_check_03

run_klayout_drc \
    -gds /openlane/designs/dpd_capture_ram_macro_100m/runs/capture_ram_signoff_100m_13/results/signoff/capture_ram_macro.gds \
    -stage capture_ram
