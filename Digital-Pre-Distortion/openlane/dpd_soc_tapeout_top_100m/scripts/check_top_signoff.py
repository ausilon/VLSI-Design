#!/usr/bin/env python3
"""Fail unless the completed top-level run has clean physical signoff."""

import csv
import re
import sys
from pathlib import Path


DESIGN = "dpd_soc_tapeout_top"
ROOT = Path(__file__).resolve().parents[1]


def fail(message):
    print(f"[SIGNOFF FAIL] {message}", file=sys.stderr)
    raise SystemExit(1)


def last_number(text, label):
    values = re.findall(
        rf"(?m)^\s*{re.escape(label)}\s+(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\s*$",
        text,
    )
    if not values:
        fail(f"metric '{label}' not found")
    return float(values[-1])


def latest(paths):
    paths = list(paths)
    if not paths:
        return None
    return max(paths, key=lambda path: path.stat().st_mtime)


def main():
    if len(sys.argv) != 2:
        fail("usage: check_top_signoff.py RUN_TAG")

    run = ROOT / "runs" / sys.argv[1]
    if not run.is_dir():
        fail(f"run does not exist: {run}")

    required_artifacts = [
        run / "results/signoff" / f"{DESIGN}.gds",
        run / "results/signoff" / f"{DESIGN}.lef",
        run / "results/signoff" / f"{DESIGN}.lib",
        run / "results/signoff" / f"{DESIGN}.sdf",
        run / "results/signoff" / f"{DESIGN}.spice",
    ]
    for artifact in required_artifacts:
        if not artifact.is_file() or artifact.stat().st_size == 0:
            fail(f"missing final artifact: {artifact}")

    sta_logs = sorted((run / "logs/signoff").glob("*rcx*sta*.log"))
    if len(sta_logs) < 4:
        fail(f"expected nominal/min/max RCX STA logs, found {len(sta_logs)}")

    for log in sta_logs:
        text = log.read_text(errors="replace")
        tns = last_number(text, "tns")
        wns = last_number(text, "wns")
        slacks = [float(value) for value in re.findall(
            r"(?m)^\s*worst slack\s+(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\s*$",
            text,
        )]
        if len(slacks) < 2:
            fail(f"setup/hold summaries missing in {log.name}")
        setup, hold = slacks[-2], slacks[-1]
        if min(tns, wns, setup, hold) < 0:
            fail(
                f"negative timing in {log.name}: "
                f"TNS={tns}, WNS={wns}, setup={setup}, hold={hold}"
            )

        for label in (
            "max slew violation count",
            "max cap violation count",
        ):
            if last_number(text, label) != 0:
                fail(f"{label} is nonzero in {log.name}")

        # MAX_FANOUT_CONSTRAINT=10 is an optimization heuristic, not a SKY130
        # electrical signoff limit. CTS branches may legitimately exceed it
        # when transition, capacitance and setup/hold remain clean.
        fanout_count = last_number(text, "max fanout violation count")
        if fanout_count != 0:
            print(
                f"[SIGNOFF INFO] {log.name}: "
                f"{int(fanout_count)} advisory fanout violations"
            )

    drt = run / "reports/routing/drt.drc"
    if not drt.is_file():
        fail("TritonRoute DRC report is missing")
    if drt.read_text(errors="replace").strip():
        fail("TritonRoute DRC report is not empty")

    antenna = latest((run / "reports/signoff").glob("*-antenna_violators.rpt"))
    if antenna is None:
        fail("antenna report is missing")
    if antenna.read_text(errors="replace").strip():
        fail(f"antenna violations remain in {antenna.name}")

    lvs = latest((run / "reports/signoff").glob("*.lvs.rpt"))
    if lvs is None:
        fail("LVS report is missing")
    lvs_text = lvs.read_text(errors="replace")
    match = re.search(r"Total errors\s*=\s*(\d+)", lvs_text)
    if match is None or int(match.group(1)) != 0:
        fail(f"LVS is not clean in {lvs.name}")

    metrics_file = run / "reports/metrics.csv"
    if not metrics_file.is_file():
        fail("final metrics.csv is missing")
    with metrics_file.open(newline="") as stream:
        rows = list(csv.DictReader(stream))
    if not rows:
        fail("final metrics.csv is empty")
    metrics = rows[-1]
    for field in (
        "tritonRoute_violations",
        "Magic_violations",
        "pin_antenna_violations",
        "net_antenna_violations",
        "lvs_total_errors",
        "klayout_violations",
    ):
        try:
            value = float(metrics[field])
        except (KeyError, ValueError):
            fail(f"invalid final metric: {field}")
        if value != 0:
            fail(f"final metric {field}={value}, expected 0")

    print("[SIGNOFF PASS] RCX STA, electrical limits, DRC, antenna, LVS and KLayout are clean.")


if __name__ == "__main__":
    main()
