# DPD SoC cleanup and DPDv1 restructuring

## Firmware / SoC base

The minimal SoC still keeps only:

- `picorv32_axi`
- SPI flash XIP at `0x0000_0000` for direct firmware boot
- AXI RAM at `0x1000_0000` for stack/data
- UART debug at `0x2000_0000`
- SPI debug/control at `0x3000_0000`
- DPD control/status at `0x4000_0000`

GPIO, I2C, timer, UART bootloader and boot manager remain removed.

## DPDv1 module structure

The previous placeholder structure was replaced by the requested DPDv1 hierarchy:

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

`mac_engine` is instantiated inside `dpd_filter`, because it is part of the fast-path DPD filter datapath.

## Removed old DPD module names

The following older names were removed from `rtl/filelist.f` and deleted from `rtl/`:

- `gmp_engine.v`
- `metrics_engine.v`
- `coef_bank.v`
- `coef_update_ctrl.v`
- `bypass_mux_sync.v`
- `supervisor_fsm.v`
- `reg_if_picorv.v`

## Current implementation status

- `axi_lite_regs.v`: AXI-Lite register block for control, status, thresholds, coefficient writes and capture/delay configuration.
- `coef_bank_a.v` / `coef_bank_b.v`: explicit A/B coefficient memories.
- `coef_switch_ctrl.v`: switches active bank only on `sync_event` and when the datapath is idle.
- `dpd_filter.v`: fast-path wrapper with bypass/DPD selection and `mac_engine`.
- `mac_engine.v`: latency-1 pass-through placeholder with coefficient read interface ready for fixed-point GMP/MP MAC implementation.
- `delay_align.v`: programmable feedback delay for REF/FB alignment.
- `capture_ram_pingpong.v`: ping-pong capture RAM shell for aligned REF/FB samples.
- `irq_status_ctrl.v`: capture, coefficient-switch and metrics-trigger IRQ/status aggregation.

## Important next step

The next RTL block to implement is `mac_engine.v`. It should be replaced with the fixed-point DPD polynomial/MAC datapath once the coefficient format, memory depth and nonlinearity/memory order are fixed.
