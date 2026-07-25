# DPD OpenLane Child Floorplans

Projetos-filho criados para montar o top fisico depois:

- `dpd_pico_100m`
- `dpd_axi_100m`
- `dpd_peripherals_100m`
- `dpd_metrics_100m`
- `dpd_capture_ram_macro_100m`
- `dpd_coef_bank_macro_100m`

Comando base dentro do container OpenLane desta maquina:

```bash
CHILD_DESIGN=<design_name> CHILD_TAG=floorplan_100m_01 \
  ./flow.tcl -interactive -file ./designs/run_child_floorplan.tcl
```

Exemplo:

```bash
CHILD_DESIGN=dpd_coef_bank_macro_100m CHILD_TAG=floorplan_100m_01 \
  ./flow.tcl -interactive -file ./designs/run_child_floorplan.tcl
```

Os blocos `dpd_capture_ram_macro_100m` e `dpd_coef_bank_macro_100m` usam SRAM
macros SKY130 para evitar memoria sintetizada em celulas padrao.

Comando para avançar placement/CTS/routing/signoff de um filho:

```bash
CHILD_DESIGN=<design_name> CHILD_TAG=signoff_100m_01 \
  ./flow.tcl -interactive -file ./designs/run_child_signoff.tcl
```

Para filhos com SRAM hard macro, usar o fluxo de macro route:

```bash
CHILD_DESIGN=dpd_coef_bank_macro_100m CHILD_TAG=macro_route_100m_01 \
  ./flow.tcl -interactive -file ./designs/run_child_macro_route.tcl
```

Nesse caso, Magic DRC/LVS interno das SRAMs fica desabilitado; o wrapper e o
roteamento ao redor sao gerados, e as SRAMs sao tratadas como macros fisicos
pre-validados.
