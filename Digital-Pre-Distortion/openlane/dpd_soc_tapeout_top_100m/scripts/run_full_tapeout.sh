#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-tapeout_full_01}"
IMAGE="ghcr.io/the-openroad-project/openlane:ff5509f65b17bfa4068d5336495ab1718987ff69-amd64"
PDK_HOST="/home/Ausilon/.ciel/ciel/sky130/versions/0fe599b2afb6708d281543108caf8310912f54af"

docker run --rm \
  -e PWD=/openlane \
  -e PDK=sky130A \
  -e PDK_ROOT=/pdkroot \
  -e CHILD_DESIGN=dpd_soc_tapeout_top_100m \
  -e CHILD_TAG="$TAG" \
  -v /home/Ausilon/openlane_work/designs:/openlane/designs \
  -v "$PDK_HOST":/pdkroot \
  "$IMAGE" \
  bash -lc 'cd /openlane && ./flow.tcl -interactive -file ./designs/run_tapeout_full_no_prefill.tcl'
