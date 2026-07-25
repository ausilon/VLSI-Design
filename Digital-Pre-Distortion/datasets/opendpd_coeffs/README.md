# OpenDPD Coefficients for rtl_v2 GMP Test

Generated with:

```bash
python3 scripts/export_q216_coeffs.py
```

Source model:

```text
/home/Ausilon/projeto_dpd/OpenDPD/save/ATSC3_A322_VV031_8K_256QAM_FS24M_AGGRESSIVE_ALIGNED/train_dpd/PA_S_0_M_GMP_H_23_F_64/DPD_S_0_M_GMP_H_15_F_64_P_39.pt
```

Files:

- `coef_bank_openDPD.hex`: 128-entry signed Q2.16/int18 coefficient bank.
- `coef_bank_openDPD_audit.csv`: float-to-Q2.16 mapping audit.
- `coef_bank_openDPD_metadata.json`: source path and extraction metadata.
- `gmp_opendpd_samples_iq_q15.hex`: packed `{I,Q}` Q1.15 input vectors.
- `gmp_opendpd_expected_iq_q15.hex`: packed `{I,Q}` expected RTL outputs.
- `gmp_opendpd_full_samples_iq_q15.hex`: 64 directed samples plus 2 zero
  lookahead flush samples for full streaming RTL validation.
- `gmp_opendpd_full_expected_iq_q15.hex`: 64 expected outputs for the full
  directed test.

Coefficient format:

```text
addr 2*k + 0 = Re{coef[k]} signed Q2.16 int18
addr 2*k + 1 = Im{coef[k]} signed Q2.16 int18
```

The checkpoint currently contains 39 real OpenDPD GMP weights, so the exported
imaginary entries are zero. The rtl_v2 `gmp_engine` implements full complex
coefficient multiplication and can consume nonzero imaginary coefficients when
the trainer/exporter produces them.

Model covered:

```text
memory_length = 3
degree        = 5
terms         = 39
lookahead     = 2 samples
```

The expected vectors are generated with integer Q-format arithmetic matching the
current RTL, including integer floor square-root for `abs(x)`.

Full directed test command:

```bash
/home/Ausilon/intelFPGA_standard/24.1std/questa_fse/linux_x86_64/vlib /tmp/dpd_gmp39_full_directed_stream_work
/home/Ausilon/intelFPGA_standard/24.1std/questa_fse/linux_x86_64/vlog -sv -work /tmp/dpd_gmp39_full_directed_stream_work rtl_v2/gmp_engine.v tb/tb_gmp_engine_opendpd.sv
/home/Ausilon/intelFPGA_standard/24.1std/questa_fse/linux_x86_64/vsim -c -lib /tmp/dpd_gmp39_full_directed_stream_work tb_gmp_engine_opendpd -do "run -all; quit"
```

Expected result:

```text
[TB PASS] tb_gmp_engine_opendpd
Errors: 0, Warnings: 0
```
