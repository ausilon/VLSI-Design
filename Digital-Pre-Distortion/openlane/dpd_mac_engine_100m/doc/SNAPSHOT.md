# dpd_mac_engine_100m

OpenLane-only synthesis target for the serialized slow-path `mac_engine`.

This snapshot is isolated from the main project RTL. The objective is to
measure area/timing for the maximally serialized internal NLMS trainer:

- 39 GMP terms;
- complex Q2.16 coefficients;
- one basis term per cycle;
- one training sample consumes roughly 80 cycles;
- 20 epochs over 1024 samples remain far below the 5 minute training target.
