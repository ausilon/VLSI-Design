# DPD Child Floorplan Summary

Run tag: `floorplan_100m_01`

| Design | Conteudo | Resultado |
|---|---|---|
| `dpd_metrics_100m` | `metric_engine` | `324.76 x 323.68 um` |
| `dpd_pico_100m` | `picorv32_ol_wrapper` | `597.54 x 595.68 um` |
| `dpd_peripherals_100m` | UART, SPI, IRQ/status | `192.28 x 190.40 um` |
| `dpd_axi_100m` | AXI-Lite interconnect + regs | `759.46 x 756.16 um` |
| `dpd_coef_bank_macro_100m` | 2 SRAM macros coef | `1219.92 x 568.48 um` |
| `dpd_capture_ram_macro_100m` | 8 SRAM macros capture | `1719.94 x 2216.80 um` |

Generated floorplan artifacts:

- `results/synthesis/*.v`
- `results/synthesis/*.sdf`
- `results/floorplan/*.def`
- `results/floorplan/*.odb`

Run one child from the OpenLane container:

```bash
CHILD_DESIGN=dpd_metrics_100m CHILD_TAG=floorplan_100m_01 \
  ./flow.tcl -interactive -file ./designs/run_child_floorplan.tcl
```

Memory macro note:

- `dpd_coef_bank_macro_100m` uses `sky130_sram_1kbyte_1rw1r_32x256_8`.
- `dpd_capture_ram_macro_100m` uses `sky130_sram_2kbyte_1rw1r_32x512_8`.
- These wrappers are physical-planning replacements for inferred memories and
  need functional timing review before becoming the final RTL contract.

## Route/Signoff Status

| Design | Run tag | Status |
|---|---|---|
| `dpd_peripherals_100m` | `signoff_100m_01` | route ok, Magic DRC ok, LVS errors=0, GDS/LEF ok |
| `dpd_metrics_100m` | `signoff_100m_01` | route ok, Magic DRC ok, LVS errors=0, GDS/LEF ok |
| `dpd_pico_100m` | `signoff_100m_01` | route ok, Magic DRC ok, LVS errors=0, GDS/LEF ok |
| `dpd_axi_100m` | `signoff_100m_01` | route ok, Magic DRC ok, LVS errors=0, GDS/LEF ok |
| `dpd_coef_bank_macro_100m` | `coef_bank_signoff_100m_04` | STA RCX 100 MHz: setup +0.16 ns, hold +0.82 ns; route/LVS/XOR clean |
| `dpd_capture_ram_macro_100m` | `capture_ram_signoff_100m_13` | STA RCX 100 MHz: setup +1.27 ns, hold +0.01 ns; route/LVS/XOR clean |

Blocos críticos já processados:

- `dpd_gmp_engine_100m`: 223170 células; global-route setup +3.16 ns e hold +0.09 ns;
- `dpd_mac_engine_100m`: candidato `mac_core_100m_05` com 131048 células;
  global-route setup +1.47 ns e hold +0.16 ns; detailed route em continuação.
