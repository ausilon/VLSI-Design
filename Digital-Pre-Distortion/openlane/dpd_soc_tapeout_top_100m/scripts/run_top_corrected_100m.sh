#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-top_v4_memfix_100m_01}"
ROOT="/home/Ausilon/openlane_work"
DESIGN="$ROOT/designs/dpd_soc_tapeout_top_100m"
RUN_DIR="$DESIGN/runs/$TAG"
IMAGE="ghcr.io/the-openroad-project/openlane:ff5509f65b17bfa4068d5336495ab1718987ff69-amd64"
PDK_HOST="/home/Ausilon/.ciel/ciel/sky130/versions/0fe599b2afb6708d281543108caf8310912f54af"

if [[ -e "$RUN_DIR" ]]; then
    echo "ERROR: run already exists: $RUN_DIR" >&2
    exit 2
fi

"$DESIGN/scripts/prepare_corrected_macro_views.sh"

docker run --rm -it \
    -e PWD=/openlane \
    -e PDK=sky130A \
    -e PDK_ROOT=/pdkroot \
    -v "$ROOT/designs":/openlane/designs \
    -v "$PDK_HOST":/pdkroot \
    "$IMAGE" \
    bash -lc "cd /openlane && ./flow.tcl \
        -design ./designs/dpd_soc_tapeout_top_100m \
        -tag '$TAG'"

python3 "$DESIGN/scripts/check_top_signoff.py" "$TAG"
