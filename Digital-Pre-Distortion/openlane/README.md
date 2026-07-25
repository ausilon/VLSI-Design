# OpenLane/SKY130 Flow

Este diretório contém apenas arquivos de projeto para reproduzir a avaliação
física em SKY130. Os diretórios `runs/` e artefatos gerados não são versionados.

O fluxo OpenLane aqui é parte da prova de conceito. Ele mostra que os blocos
podem ser levados até síntese, floorplan, roteamento e signoff preliminar em um
PDK aberto, mas ainda não substitui um fluxo industrial completo de tapeout.
Resultados como área, densidade, DRC/LVS e Fmax devem ser interpretados como
evidências de engenharia para orientar a próxima iteração.

## Projetos

| Projeto | Descrição |
|---|---|
| `dpd_gmp_engine_100m` | macro do GMPengine |
| `dpd_mac_engine_100m` | macro do MACcore |
| `dpd_metrics_100m` | MetricEngine |
| `dpd_pico_100m` | PicoRV32 wrapper |
| `dpd_axi_100m` | AXI-Lite/control wrapper |
| `dpd_peripherals_100m` | UART/SPI/IRQ wrapper |
| `dpd_capture_ram_macro_100m` | Capture RAM com SRAM hard macros |
| `dpd_coef_bank_macro_100m` | bancos de coeficientes com SRAM hard macros |
| `dpd_soc_macro_top_100m` | montagem física macro-level preliminar |
| `dpd_soc_tapeout_top_100m` | scaffold de top físico para tapeout futuro |

## Scripts

| Script | Uso |
|---|---|
| `run_child_floorplan.tcl` | floorplan inicial dos blocos filhos |
| `run_child_signoff.tcl` | fluxo completo para blocos standard-cell |
| `run_child_macro_route.tcl` | fluxo para blocos com SRAM macro |
| `run_gmp_timing_push_110m.tcl` | tentativa agressiva para fechar GMP >96 MHz |
| `run_mac_signoff_no_prefill.tcl` | fluxo do MACcore com menor pressão de memória |
| `run_tapeout_continue_after_cts_no_resizer.tcl` | continuação do top scaffold sem routing resizer |

## Resultado Atual

Macros menores fecharam DRC/LVS. `GMPengine` e `MACcore` foram processados como
blocos críticos. O top macro-level gerou GDS para documentação e avaliação de
floorplan, mas ainda não representa tapeout final porque falta padframe,
conectividade funcional completa e signoff temporal do chip completo.

Essa limitação é intencionalmente documentada para manter o trabalho honesto: o
GDS preliminar é útil para discutir área, organização de macros e complexidade
física, mas não deve ser enviado à foundry como chip funcional.

## Comando Base

Exemplo:

```bash
cd /home/Ausilon/openlane_work
docker run --rm -it \
  -e PDK=sky130A \
  -e PDK_ROOT=/pdkroot \
  -v /home/Ausilon/openlane_work/designs:/openlane/designs \
  -v /home/Ausilon/.ciel/ciel/sky130/versions/0fe599b2afb6708d281543108caf8310912f54af:/pdkroot \
  ghcr.io/the-openroad-project/openlane:ff5509f65b17bfa4068d5336495ab1718987ff69-amd64 \
  bash -lc 'cd /openlane && ./flow.tcl -interactive -file ./designs/run_gmp_timing_push_110m.tcl'
```
