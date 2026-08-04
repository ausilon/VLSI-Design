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

## Baseline Física Comum

As oito macros são comparadas no checkpoint comum de STA single-corner
pós-global-route, com período-alvo de 10 ns. Resultados posteriores permanecem
evidências individuais e não são classificados como signoff uniforme.

| Macro | Run auditado | Células | Área macro (mm²) | Setup pós-GRT (ns) | Hold pós-GRT (ns) | Dominante Cell |
|---|---|---:|---:|---:|---:|---|
| PicoRV32 | `signoff_100m_01` | 10.114 | 0,377 | +3,41 | +0,15 | `sky130_fd_sc_hd__buf_1` (2.422) |
| AXI control | `signoff_100m_01` | 1.713 | 0,640 | +3,58 | +0,21 | `sky130_fd_sc_hd__buf_1` (395) |
| Peripherals | `signoff_100m_01` | 755 | 0,044 | +4,21 | +0,19 | `sky130_fd_sc_hd__dfrtp_2` (183) |
| MetricEngine | `signoff_100m_01` | 2.593 | 0,116 | +2,94 | +0,24 | `sky130_fd_sc_hd__nand2_2` (272) |
| Capture RAM | `capture_ram_signoff_100m_13` | 741 (inclui 8 SRAM) | 4,140 | +3,93 | +0,26 | `sky130_fd_sc_hd__dfxtp_2` (320) |
| Coef Bank | `coef_bank_signoff_100m_04` | 154 (inclui 2 SRAM) | 0,845 | +1,84 | +1,65 | `sky130_fd_sc_hd__buf_1` (56) |
| GMPengine | `gmp_feature_piped_route_relaxed_100m_01` | 223.170 | 11,497 | +3,16 | +0,09 | `sky130_fd_sc_hd__nand2_2` (79.930) |
| MACcore | `mac_core_100m_05` | 131.048 | 7,758 | +1,47 | +0,16 | `sky130_fd_sc_hd__nand2_2` (35.921) |

Os slacks positivos valem para os caminhos restritos desse checkpoint. Eles não
substituem STA RCX multicorner e não constituem declaração de Fmax ou signoff.
