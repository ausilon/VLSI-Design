package require openlane

prep -design ./designs/dpd_coef_bank_macro_100m \
    -tag coef_bank_klayout_drc_check_02

run_klayout_drc \
    -gds /openlane/designs/dpd_coef_bank_macro_100m/runs/coef_bank_signoff_100m_04/results/signoff/coef_bank_macro.gds \
    -stage coef_bank
