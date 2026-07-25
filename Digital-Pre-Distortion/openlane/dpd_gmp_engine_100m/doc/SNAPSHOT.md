# GMP engine OpenLane 100 MHz snapshot

Origem do RTL:

`/home/Ausilon/Desktop/dpd_v1/dpd_soc_min/rtl_v2/gmp_engine.v`

Design OpenLane:

`/home/Ausilon/openlane_work/designs/dpd_gmp_engine_100m`

Top:

`gmp_engine_ol_wrapper`

Objetivo:

- Sintetizar o fast path GMP isolado.
- Avaliar se o pipeline atual fecha 100 MHz em SKY130.
- Medir area inicial do bloco de inferencia sem AXI, capture RAM e MACcore.

Configuracao inicial:

- `CLOCK_PERIOD = 10 ns`
- `FP_CORE_UTIL = 25`
- `PL_TARGET_DENSITY = 0.40`
- standard cell: `sky130_fd_sc_hd`

Observacao:

O wrapper registra entradas e saidas para evitar que o primeiro STA seja
dominado por caminhos IO combinacionais. O resultado mede o comportamento do
bloco em fronteiras sincronas.
