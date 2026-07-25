# DPD SoC Tapeout Top Runbook

This directory is the top-level tapeout candidate package for OpenLane.

## Scope

This run attempts top-level closure around the already hardened child macros:

- `gmp_engine_ol_wrapper`
- `mac_engine`
- `picorv32_ol_wrapper`
- `axi_ctrl_wrapper`
- `metric_engine`
- `peripherals_wrapper`
- `capture_ram_macro`
- `coef_bank_macro`

The first mandatory checkpoint is strict top-level PDN. If PDN fails, do not run
full routing; adjust PDN pitch/offset/halos or macro placement first.

## Step 1 - PDN Check

```bash
cd /home/Ausilon/openlane_work
./designs/dpd_soc_tapeout_top_100m/scripts/run_pdn_check.sh tapeout_pdn_check_01
```

Monitor:

```bash
./designs/dpd_soc_tapeout_top_100m/scripts/monitor_tapeout.sh tapeout_pdn_check_01
```

PDN pass criteria:

- flow reaches `save_state`;
- no `PSM-0069`;
- no top-level disconnected `VPWR/VGND` nodes.

### PDN Attempt Notes

`tapeout_pdn_check_01` failed at `pdn.tcl` with:

```text
PSM-0069 Check connectivity failed
Unconnected PDN node on VPWR
```

The failing nodes appeared in the upper/right macro region around GMP. This
points to disconnected top-level macro-grid fragments, not a failure of the
already closed internal PDN inside the child macros.

Applied next-attempt changes:

```json
"FP_PDN_ENABLE_MACROS_GRID": false,
"FP_PDN_VPITCH": 260,
"FP_PDN_HPITCH": 260,
"FP_PDN_VERTICAL_HALO": 60,
"FP_PDN_HORIZONTAL_HALO": 60
```

Recommended next tag:

```bash
./designs/dpd_soc_tapeout_top_100m/scripts/run_pdn_check.sh tapeout_pdn_check_02
```

`tapeout_pdn_check_02` also failed with `PSM-0069`. The run configuration had
`FP_PDN_ENABLE_MACROS_GRID=0`, but the OpenLane default `pdn_cfg.tcl` still
instantiated a default macro PDN grid unconditionally:

```text
Inserting grid: macro - u_gmp
Inserting grid: macro - u_mac
...
```

The top-level PDN was then changed to use:

```text
pdn_tapeout_cfg.tcl
```

This custom PDN keeps the top grid explicit:

- `met1`: standard-cell rails;
- `met4`: vertical top-level power straps;
- `met5`: horizontal top-level power straps;
- `met4/met5`: core ring;
- no automatic top-level macro grid.

`tapeout_pdn_check_03` passed the PDN checkpoint:

```text
All PDN stripes on net VPWR are connected.
All PDN stripes on net VGND are connected.
```

Remaining warnings about `VSRC` are expected at this stage because the final
padframe/power-source locations are not yet declared. They are not the previous
connectivity failure, but must be closed before a real tapeout package.

## Step 2 - Full Macro Top Signoff Attempt

Run only after PDN check passes.

```bash
cd /home/Ausilon/openlane_work
./designs/dpd_soc_tapeout_top_100m/scripts/run_full_tapeout.sh tapeout_full_01
```

Monitor:

```bash
./designs/dpd_soc_tapeout_top_100m/scripts/monitor_tapeout.sh tapeout_full_01
```

### Full Flow Attempt Notes

`tapeout_full_02` reached CTS and then failed at routing resizer:

```text
RSZ-0005 Run global_route before estimating parasitics for global routing.
Routed nets: 0
```

This is expected for the current macro-level scaffold because most functional
inter-macro signal nets are still intentionally absent. The hard macros are
placed and powered, but this is not yet the final connected production top.

The full-flow script now skips:

```text
run_resizer_design_routing
run_resizer_timing_routing
```

until the production top netlist is connected.

To continue the existing `tapeout_full_02` run from CTS:

```bash
cd /home/Ausilon/openlane_work
./designs/dpd_soc_tapeout_top_100m/scripts/continue_after_cts_no_resizer.sh tapeout_full_02
```

`tapeout_full_03` used the corrected macro-scaffold flow:

- routing resizers disabled;
- heuristic antenna repair disabled;
- detailed routing disabled because global route produced zero signal guides;
- Magic GDS/LEF/SPICE generated;
- Magic DRC passed with no violations after GDS stream-out.

Important result:

```text
No DRC violations after GDS streaming out.
LVS total errors = 35
```

LVS does not close because the current top is still a physical macro scaffold,
not the final connected production top. The report shows:

```text
net count difference = 16
unmatched nets = 3
unmatched devices = 16
```

Generated artifacts:

```text
results/signoff/dpd_soc_tapeout_top.gds
results/signoff/dpd_soc_tapeout_top.klayout.gds
results/signoff/dpd_soc_tapeout_top.lef
results/signoff/dpd_soc_tapeout_top.spice
```

This GDS is useful for area/floorplan review and documentation, but is not a
foundry-ready functional chip.

## Important Limitations

This package is a physical tapeout candidate scaffold. The current top still
uses macro-level assembly and does not yet include a reviewed production
padframe or all functional inter-macro signal connections. Treat successful
OpenLane completion as physical-flow progress, not final tapeout authorization.

Before real tapeout, complete:

- production padframe;
- final top-level Verilog connectivity;
- top-level PDN signoff;
- top-level signal routing;
- DRC/LVS/CVC;
- STA with realistic constraints;
- antenna checks;
- package/pinout review.
