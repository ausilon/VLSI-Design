#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-tapeout_full_01}"
RUN="/home/Ausilon/openlane_work/designs/dpd_soc_tapeout_top_100m/runs/$TAG"

echo "== Docker containers =="
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Command}}'
echo

echo "== Docker resources =="
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' || true
echo

if [ -f "$RUN/openlane.log" ]; then
  echo "== OpenLane tail: $RUN/openlane.log =="
  tail -n 60 "$RUN/openlane.log"
else
  echo "Run log not found yet: $RUN/openlane.log"
fi

echo
echo "== Latest step logs =="
find "$RUN/logs" -type f -printf '%TY-%Tm-%Td %TH:%TM:%TS %p %s\n' 2>/dev/null | sort | tail -n 12 || true
