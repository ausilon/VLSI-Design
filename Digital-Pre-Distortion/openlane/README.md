# Fluxo OpenLane/SKY130

Este diretório contém a preparação física do projeto para SKY130 usando
OpenLane. São mantidos apenas arquivos de projeto: RTL adaptado para OpenLane,
wrappers, `config.json`, `pin_order.cfg`, scripts Tcl e documentação. Os
diretórios `runs/` não são versionados porque contêm resultados gerados,
temporários, logs e bancos de dados físicos.

O objetivo desta etapa é medir área, observar congestionamento, identificar
gargalos de timing e construir uma organização física inicial para o SoC. O
fluxo segue a mesma lógica modular usada no HDL: primeiro blocos menores, depois
os blocos críticos e, por último, a montagem top-level.

---

# Ambiente

O OpenLane é executado em Docker para manter a versão das ferramentas e do PDK
controlada. O fluxo usa Yosys para síntese, OpenROAD para floorplan, placement,
CTS e roteamento, Magic para DRC/GDS e Netgen para LVS. O PDK utilizado é o
SkyWater SKY130 com standard cells `sky130_fd_sc_hd`.

O comando base usado nas rodadas locais segue o padrão:

```bash
cd /home/Ausilon/openlane_work
docker run --rm -it \
  -e PDK=sky130A \
  -e PDK_ROOT=/pdkroot \
  -v /home/Ausilon/openlane_work/designs:/openlane/designs \
  -v /home/Ausilon/.ciel/ciel/sky130/versions/0fe599b2afb6708d281543108caf8310912f54af:/pdkroot \
  ghcr.io/the-openroad-project/openlane:ff5509f65b17bfa4068d5336495ab1718987ff69-amd64 \
  bash -lc 'cd /openlane && ./flow.tcl -interactive -file ./designs/run_child_signoff.tcl'
```

---

# Estratégia Modular

Os blocos foram separados em projetos filhos. Essa organização reduz o tempo de
debug, permite avaliar área por bloco e evita que problemas de um macro impeçam
a análise dos demais.

| Projeto | Papel físico |
|---|---|
| `dpd_pico_100m` | macro do PicoRV32 |
| `dpd_axi_100m` | AXI-Lite e registradores |
| `dpd_peripherals_100m` | UART, SPI e IRQ/status |
| `dpd_metrics_100m` | MetricEngine |
| `dpd_capture_ram_macro_100m` | RAM de captura com SRAM hard macros |
| `dpd_coef_bank_macro_100m` | bancos de coeficientes com SRAM hard macros |
| `dpd_gmp_engine_100m` | motor de inferência GMP |
| `dpd_mac_engine_100m` | motor de treinamento NLMS |
| `dpd_soc_tapeout_top_100m` | montagem top-level física |

As memórias foram tratadas como macros porque sintetizar grandes RAMs em células
padrão aumentaria muito a área. Essa decisão aproxima o estudo físico de uma
implementação ASIC realista.

---

# Blocos Críticos

O `GMPengine` é o bloco mais crítico em timing. Ele pertence ao caminho rápido e
precisa sustentar o fluxo de amostras. A versão OpenLane serializa a acumulação
dos 39 termos em quatro fases, reduzindo área, mas exigindo clock acima de
96 MHz para atingir 24 MS/s.

O `MACcore` é maior que um bloco de controle comum, mas não precisa operar na
taxa de amostragem. Ele lê snapshots da RAM e executa treinamento em background.
Por isso, a arquitetura foi mais serializada, privilegiando redução de área em
vez de latência mínima.

---

# Resultado Atual

As macros menores chegaram a signoff com DRC/LVS limpos. Os blocos com SRAM
foram roteados como macros físicas. O `GMPengine` e o `MACcore` foram avaliados
como blocos críticos e forneceram estimativas importantes de área e timing.

O top-level físico atual organiza as macros conforme o floorplan discutido para
o chip, mas ainda não é o fechamento final do circuito. Ele serve para avaliar
ocupação, relação entre os blocos, necessidade de padframe e próximos ajustes de
PDN/roteamento.

---

# Scripts Principais

| Script | Uso |
|---|---|
| `run_child_floorplan.tcl` | floorplan inicial de blocos filhos |
| `run_child_signoff.tcl` | fluxo completo para blocos standard-cell |
| `run_child_macro_route.tcl` | fluxo para blocos com SRAM macro |
| `run_gmp_timing_push_110m.tcl` | tentativa para fechar GMP acima de 96 MHz |
| `run_mac_signoff_no_prefill.tcl` | fluxo do MACcore com menor pressão de memória |
| `run_tapeout_continue_after_cts_no_resizer.tcl` | continuação do top scaffold |

O script `run_gmp_timing_push_110m.tcl` foi criado para tentar fechar o
`GMPengine` com alvo de 9 ns, sem alterar o algoritmo nem o floorplan básico da
macro.
