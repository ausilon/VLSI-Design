// Physical top-level macro assembly for the preliminary DPD SoC floorplan.
// This view preserves hardened child macros and their relative placement.
module dpd_soc_macro_top (
    input wire clk,
    input wire resetn
);
    (* keep *) picorv32_ol_wrapper    u_pico();
    (* keep *) axi_ctrl_wrapper       u_axi();
    (* keep *) peripherals_wrapper    u_peripherals();
    (* keep *) metric_engine          u_metrics();
    (* keep *) gmp_engine_ol_wrapper  u_gmp();
    (* keep *) capture_ram_macro      u_capture_ram();
    (* keep *) coef_bank_macro        u_coef_bank();
    (* keep *) mac_engine             u_mac();
endmodule
