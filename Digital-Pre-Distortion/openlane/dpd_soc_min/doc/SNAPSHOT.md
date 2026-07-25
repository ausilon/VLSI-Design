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
- O clock inicial em `config.json` esta em 20 ns, equivalente a 50 MHz.
- A taxa funcional do projeto validada ate aqui e 24 Msps; 50 MHz da margem
  para investigar timing antes de decidir o clock final.
- `pin_order.cfg` e provisório e deve ser refinado depois da primeira sintese.
