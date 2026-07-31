#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/Ausilon/openlane_work/designs"
TOP="$ROOT/dpd_soc_tapeout_top_100m"

MAC_RUN="$ROOT/dpd_mac_engine_100m/runs/mac_core_100m_05/results/signoff"
CAP_RUN="$ROOT/dpd_capture_ram_macro_100m/runs/capture_ram_signoff_100m_13/results/final"
COEF_RUN="$ROOT/dpd_coef_bank_macro_100m/runs/coef_bank_signoff_100m_04/results/final"

required=(
    "$MAC_RUN/mac_engine.gds"
    "$MAC_RUN/mac_engine.lef"
    "$MAC_RUN/mac_engine.lib"
    "$CAP_RUN/gds/capture_ram_macro.gds"
    "$CAP_RUN/lef/capture_ram_macro.lef"
    "$CAP_RUN/lib/capture_ram_macro.lib"
    "$COEF_RUN/gds/coef_bank_macro.gds"
    "$COEF_RUN/lef/coef_bank_macro.lef"
    "$COEF_RUN/lib/coef_bank_macro.lib"
)

for file in "${required[@]}"; do
    if [[ ! -s "$file" ]]; then
        echo "ERROR: required macro view is missing or empty: $file" >&2
        exit 2
    fi
done

install -m 0644 "$MAC_RUN/mac_engine.lef" "$TOP/lef_top/mac_engine.lef"
install -m 0644 "$MAC_RUN/mac_engine.lib" "$TOP/lib_top/mac_engine.lib"
install -m 0644 "$CAP_RUN/lef/capture_ram_macro.lef" "$TOP/lef_top/capture_ram_macro.lef"
install -m 0644 "$CAP_RUN/lib/capture_ram_macro.lib" "$TOP/lib_top/capture_ram_macro.lib"
install -m 0644 "$COEF_RUN/lef/coef_bank_macro.lef" "$TOP/lef_top/coef_bank_macro.lef"
install -m 0644 "$COEF_RUN/lib/coef_bank_macro.lib" "$TOP/lib_top/coef_bank_macro.lib"

echo "Corrected MACcore, Capture RAM and Coef Bank views installed in top."
