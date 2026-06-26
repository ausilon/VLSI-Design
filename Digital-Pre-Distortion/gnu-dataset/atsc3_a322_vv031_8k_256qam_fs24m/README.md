# ATSC 3.0 256QAM fs24m_262k Dataset

Generated from `/home/Ausilon/Desktop/dpd_v1/dpd_soc_min/datasets/atsc3_a322_vv031_8k_256qam_fs24m/atsc3_a322_vv031_8k_256qam_baseband_fs24m_complex64.bin`.

- Source sample rate: 24000000.000000 Sa/s
- Output sample rate: 24000000.000000 Sa/s
- Channel bandwidth: 6000000 Hz
- Resampling ratio: 1/1
- Source samples used: 262144
- Output samples: 262144
- Q15 scale: 9001.626247186
- Feedback model: one-sample delay plus nonlinear artificial PA model

The RTL files keep the same names as the previous dataset so the Questa
testbench can be redirected by changing only the dataset folder.

ATSC 3.0 baseband note:
This dataset is produced by the `gr-atsc3` `vv031` transmitter chain at
6.912 Msps and then resampled by `125/36` to 24 Msps before Q15 conversion.
The detailed ATSC 3.0 profile is recorded in `baseband_metadata.json`.

The OpenDPD companion dataset is stored at:
`/home/Ausilon/projeto_dpd/OpenDPD/datasets/ATSC3_A322_VV031_8K_256QAM_FS24M_AGGRESSIVE_ALIGNED`
