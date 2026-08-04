# DPD OpenLane RTL snapshot

Origem:

`/home/Ausilon/Desktop/dpd_v1/dpd_soc_min/rtl_v2`

Destino:

`/home/Ausilon/openlane_work/designs/dpd_soc_min/src`

Top inicial para OpenLane:

`dpd_top`

Observacoes:

- Este snapshot foi criado para exploracao de sintese/floorplan em SKY130.
- O alvo inicial e o subsistema DPD, nao o SoC completo com PicoRV32.
- O clock de 20 ns deste diretório pertence somente ao snapshot exploratório
  inicial do subsistema `dpd_top`; ele não integra a baseline física consolidada.
- A baseline comparativa posterior das macros usa período-alvo de 10 ns.
- `pin_order.cfg` e provisório e deve ser refinado depois da primeira sintese.
