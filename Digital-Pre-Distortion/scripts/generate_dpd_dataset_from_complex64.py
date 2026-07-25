#!/usr/bin/env python3
import argparse
import json
from pathlib import Path

import numpy as np
from scipy.signal import resample_poly


def q15_word(i_val, q_val):
    i_u = int(np.int16(i_val)) & 0xFFFF
    q_u = int(np.int16(q_val)) & 0xFFFF
    return f"{i_u:04X}{q_u:04X}"


def write_hex(path, words):
    with open(path, "w", encoding="ascii") as f:
        for word in words:
            f.write(word + "\n")


def make_feedback(ref_i, ref_q, delay, pa_profile):
    src_i = np.zeros_like(ref_i)
    src_q = np.zeros_like(ref_q)
    if delay > 0:
        src_i[delay:] = ref_i[:-delay]
        src_q[delay:] = ref_q[:-delay]
    else:
        src_i[:] = ref_i
        src_q[:] = ref_q

    x0 = (src_i.astype(np.float64) + 1j * src_q.astype(np.float64)) / 32768.0

    if pa_profile == "mild":
        x = x0
        r2 = np.abs(x) ** 2
        amp = 0.94 - 0.18 * r2
        phase = 0.045 * r2
        y = x * amp * np.exp(1j * phase)
    elif pa_profile == "aggressive":
        taps = [
            (1.000, 0),
            (0.095 * np.exp(1j * 0.18), 1),
            (-0.040 * np.exp(-1j * 0.33), 2),
            (0.020 * np.exp(1j * 0.55), 3),
            (-0.010 * np.exp(-1j * 0.70), 4),
        ]
        x = np.zeros_like(x0)
        for coeff, tap in taps:
            if tap == 0:
                x += coeff * x0
            else:
                x[tap:] += coeff * x0[:-tap]

        r2 = np.abs(x) ** 2
        r4 = r2 ** 2
        r6 = r2 ** 3
        amp = 0.97 - 0.55 * r2 + 0.18 * r4 - 0.045 * r6
        amp = np.clip(amp, 0.38, 1.15)
        phase = 0.18 * r2 + 0.11 * r4 + 0.035 * r6
        y_main = x * amp * np.exp(1j * phase)

        # Memory-polynomial residue that is deliberately stronger than the RTL
        # target. This stresses the GMP training without changing the baseband.
        env = np.abs(x0) ** 2
        mem = np.zeros_like(x0)
        mem[1:] += 0.060 * x0[:-1] * env[:-1]
        mem[2:] += -0.030j * x0[:-2] * (env[:-2] ** 2)
        y = y_main + mem
    else:
        raise ValueError(f"Unsupported PA profile: {pa_profile}")

    fb_i = np.clip(np.rint(y.real * 32768.0), -32768, 32767).astype(np.int16)
    fb_q = np.clip(np.rint(y.imag * 32768.0), -32768, 32767).astype(np.int16)
    return fb_i, fb_q


def split_open_dpd(x_iq, y_iq, out_dir):
    n = min(len(x_iq), len(y_iq))
    n_train = int(n * 2 / 3)
    n_val = int(n / 6)
    splits = {
        "train": (x_iq[:n_train], y_iq[:n_train]),
        "val": (x_iq[n_train:n_train + n_val], y_iq[n_train:n_train + n_val]),
        "test": (x_iq[n_train + n_val:], y_iq[n_train + n_val:]),
    }
    for split, (x_split, y_split) in splits.items():
        x_split.astype(np.float32).tofile(out_dir / f"{split}_x_clean.bin")
        y_split.astype(np.float32).tofile(out_dir / f"{split}_y_pa.bin")
    return {k: len(v[0]) for k, v in splits.items()}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-complex64", required=True)
    parser.add_argument("--rtl-out-dir", required=True)
    parser.add_argument("--opendpd-out-dir", required=True)
    parser.add_argument("--source-fs", type=float, required=True)
    parser.add_argument("--resample-up", type=int, default=1)
    parser.add_argument("--resample-down", type=int, default=1)
    parser.add_argument("--source-samples", type=int, default=262144)
    parser.add_argument("--feedback-delay", type=int, default=1)
    parser.add_argument("--output-label", default="fs24m")
    parser.add_argument("--pa-profile", choices=["mild", "aggressive"], default="mild")
    parser.add_argument("--standard", default="DVB-T2")
    parser.add_argument("--phy-reference", default="")
    parser.add_argument("--modulation", default="64QAM")
    parser.add_argument("--channel-bw-hz", type=int, default=6000000)
    parser.add_argument("--file-prefix", default="dvbt2_64qam45_baseband")
    parser.add_argument("--extra-metadata-json", default="")
    args = parser.parse_args()

    source_path = Path(args.source_complex64)
    rtl_out = Path(args.rtl_out_dir)
    opendpd_out = Path(args.opendpd_out_dir)
    rtl_out.mkdir(parents=True, exist_ok=True)
    opendpd_out.mkdir(parents=True, exist_ok=True)

    src = np.fromfile(source_path, dtype=np.complex64, count=args.source_samples)
    if len(src) != args.source_samples:
        raise RuntimeError(f"Requested {args.source_samples} samples, found {len(src)}")

    if args.resample_up == 1 and args.resample_down == 1:
        os_signal = src.astype(np.complex64)
    else:
        os_signal = resample_poly(src, args.resample_up, args.resample_down).astype(np.complex64)
    peak = float(np.max(np.abs(os_signal)))
    scale = 0.90 * 32767.0 / peak

    ref_i = np.clip(np.rint(os_signal.real * scale), -32768, 32767).astype(np.int16)
    ref_q = np.clip(np.rint(os_signal.imag * scale), -32768, 32767).astype(np.int16)
    fb_i, fb_q = make_feedback(ref_i, ref_q, args.feedback_delay, args.pa_profile)

    ref_words = [q15_word(i, q) for i, q in zip(ref_i, ref_q)]
    fb_words = [q15_word(i, q) for i, q in zip(fb_i, fb_q)]

    write_hex(rtl_out / "ref_iq_q15.hex", ref_words)
    write_hex(rtl_out / "feedback_iq_q15.hex", fb_words)
    write_hex(rtl_out / f"{args.file_prefix}_{args.output_label}_q15_{len(ref_words)}.hex", ref_words)
    write_hex(rtl_out / "expected_capture_hi_delay0.hex", ref_words[1:])
    write_hex(rtl_out / "expected_capture_lo_delay0.hex", fb_words[1:])

    iq16 = np.column_stack([ref_i, ref_q]).astype(np.int16)
    iq16.tofile(rtl_out / f"{args.file_prefix}_{args.output_label}_iq16.bin")
    os_signal.astype(np.complex64).tofile(rtl_out / f"{args.file_prefix}_{args.output_label}_complex64.bin")

    x_float = np.column_stack([ref_i, ref_q]).astype(np.float32) / 32768.0
    y_float = np.column_stack([fb_i, fb_q]).astype(np.float32) / 32768.0
    x_aligned = x_float[:-args.feedback_delay]
    y_aligned = y_float[args.feedback_delay:]
    split_samples = split_open_dpd(x_aligned, y_aligned, opendpd_out)
    extra_metadata = {}
    if args.extra_metadata_json:
        with open(args.extra_metadata_json, "r", encoding="ascii") as f:
            extra_metadata = json.load(f)

    fs = args.source_fs * args.resample_up / args.resample_down
    nperseg = 4096 if len(os_signal) >= 4096 else 1024
    spec = {
        "description": f"{args.standard} {args.modulation} dataset generated from complex64 source, with RTL-compatible artificial PA feedback",
        "dataset_format": "split_bin_complex64",
        "standard": args.standard,
        "phy_reference": args.phy_reference,
        "modulation": args.modulation,
        "source_dataset": str(source_path),
        "output_label": args.output_label,
        "resample_up": args.resample_up,
        "resample_down": args.resample_down,
        "source_samples": args.source_samples,
        "output_samples": int(len(os_signal)),
        "feedback_model": f"1-sample delay plus {args.pa_profile} artificial PA model",
        "pa_profile": args.pa_profile,
        "alignment": {
            "operation": f"x=ref[:-{args.feedback_delay}], y=feedback[{args.feedback_delay}:]",
            "reason": "remove synthetic feedback delay before OpenDPD inverse training",
        },
        "rtl_target": {
            "memory_taps": 3,
            "basis": ["x", "x|x|^2", "x|x|^4"],
            "coef_format": "signed Q2.16",
        },
        "input_signal_fs": fs,
        "bw_main_ch": args.channel_bw_hz,
        "bw_sub_ch": args.channel_bw_hz,
        "n_sub_ch": 1,
        "nperseg": nperseg,
        "split_samples": split_samples,
        "normalization": "Q1.15 hex converted to float complex in [-1, 1)",
    }
    if extra_metadata:
        spec["baseband_profile"] = extra_metadata
    with open(opendpd_out / "spec.json", "w", encoding="ascii") as f:
        json.dump(spec, f, indent=2)

    meta = dict(spec)
    meta.update({
        "q15_scale": scale,
        "source_peak": peak,
        "rms_float": float(np.sqrt(np.mean(np.abs(os_signal) ** 2))),
        "peak_q15_fraction": float(np.max(np.hypot(ref_i.astype(np.float64), ref_q.astype(np.float64))) / 32768.0),
        "rtl_files": [
            "ref_iq_q15.hex",
            "feedback_iq_q15.hex",
            "expected_capture_hi_delay0.hex",
            "expected_capture_lo_delay0.hex",
        ],
    })
    with open(rtl_out / "metadata.json", "w", encoding="ascii") as f:
        json.dump(meta, f, indent=2)

    readme = f"""# {args.standard} {args.modulation} {args.output_label} Dataset

Generated from `{source_path}`.

- Source sample rate: {args.source_fs:.6f} Sa/s
- Output sample rate: {fs:.6f} Sa/s
- Channel bandwidth: {args.channel_bw_hz} Hz
- Resampling ratio: {args.resample_up}/{args.resample_down}
- Source samples used: {args.source_samples}
- Output samples: {len(os_signal)}
- Q15 scale: {scale:.9f}
- Feedback model: one-sample delay plus {args.pa_profile} artificial PA model

The RTL files keep the same names as the previous dataset so the Questa
testbench can be redirected by changing only the dataset folder.

The OpenDPD companion dataset is stored at:
`{opendpd_out}`
"""
    with open(rtl_out / "README.md", "w", encoding="ascii") as f:
        f.write(readme)

    print(json.dumps({
        "rtl_out_dir": str(rtl_out),
        "opendpd_out_dir": str(opendpd_out),
        "fs": fs,
        "samples": int(len(os_signal)),
        "split_samples": split_samples,
        "q15_scale": scale,
    }, indent=2))


if __name__ == "__main__":
    main()
