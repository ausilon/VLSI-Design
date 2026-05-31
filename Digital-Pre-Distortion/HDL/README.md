# dpd_soc_min

Minimal PicoRV32 AXI SoC prepared as a controller for the DPD project.

## Kept from the base SoC

- PicoRV32 AXI CPU
- SPI flash XIP firmware boot
- AXI RAM for stack/data
- AXI UART for debug/log
- AXI SPI for debug/control
- AXI-Lite DPD control/status peripheral

## Removed

- UART bootloader
- boot manager
- GPIO
- I2C
- timer
- old DPD placeholder names from the previous iteration

## Memory map

| Base address | Region |
|---:|---|
| `0x0000_0000` | SPI flash XIP firmware |
| `0x1000_0000` | RAM |
| `0x2000_0000` | UART debug |
| `0x3000_0000` | SPI debug/control |
| `0x4000_0000` | DPD AXI-Lite control/status |

## DPDv1 hierarchy

```text
dpd_top
├── axi_lite_regs
├── dpd_filter
├── coef_bank_a
├── coef_bank_b
├── coef_switch_ctrl
├── capture_ram_pingpong
├── delay_align
├── mac_engine
└── irq_status_ctrl
```

`mac_engine` is instantiated inside `dpd_filter` because it belongs to the fast datapath.

## Current behavior

The DPD datapath is structurally connected, but `mac_engine.v` is still a pass-through placeholder. This is intentional: the SoC/register/control skeleton is now aligned with the diagram and ready for the real fixed-point DPD MAC implementation.

The CPU can:

- write coefficient bank A or B;
- request a glitch-free bank switch at `sync_event`;
- configure feedback delay;
- start capture into ping-pong RAM;
- read metrics/status/IRQ registers.

## Suggested compile check

```bash
cd dpd_soc_min
iverilog -g2012 -o sim_check.vvp $(cat rtl/filelist.f)
```

If your toolchain is strict Verilog-2001, use `-g2005-sv` or synthesize with Yosys after replacing the placeholder `mac_engine.v` with the target implementation.
