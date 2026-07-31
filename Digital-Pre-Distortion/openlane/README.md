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
96 MHz para atingir 24 MS/s. A implementação atual usa dez lanes com pipeline
de latência fixa; em 100 MHz, o contrato `II=4` fornece 25 MS/s.

O `MACcore` é maior que um bloco de controle comum, mas não precisa operar na
taxa de amostragem. Ele lê snapshots da RAM e executa treinamento em background.
Por isso, a arquitetura foi mais serializada, privilegiando redução de área em
vez de latência mínima.

---

# Resultado Atual

O `GMPengine` preservado possui 223.170 células e área de 11,498 mm². Seu STA
pós-global-route em 100 MHz apresenta setup de `+3,16 ns` e hold de `+0,09 ns`.
O detailed route, Magic DRC e LVS foram concluídos sem erros, mas ainda falta
STA RCX multicorner para classificá-lo como fechado temporalmente.

O candidato atual do `MACcore`, `mac_core_100m_05`, possui 131.048 células e
área de 7,659 mm². Antes do detailed routing apresentou setup de `+1,47 ns` e
hold de `+0,16 ns`. O primeiro DRT deixou um único short em met1; o script de
continuação reaproveita o checkpoint pós-global-route e aumenta o limite para
24 iterações.

A Capture RAM e o Coef Bank foram refeitos com fronteiras registradas, pin
placement orientado pelos ports das SRAMs e CTS específico. Ambos fecham
100 MHz em STA pós-route multicorner: `+1,27/+0,01 ns` para setup/hold da
Capture RAM e `+0,16/+0,82 ns` para o Coef Bank. TritonRoute, LVS e XOR estão
limpos. Violações reportadas pelo Magic dentro das células OpenRAM fornecidas
são mantidas como ressalva explícita.

O top atual é funcionalmente conectado, possui PDN hierárquica e die de trabalho
de `8,5 x 8,5 mm`. O pinout reserva 108 sinais funcionais, quatro sinais DFT e
16 alimentações para um futuro `aQFN/DRQFN-128`. O próximo run físico é
`top_v4_memfix_100m_01`, após a conclusão do novo MACcore. Padframe, IR drop,
potência e signoff de chip permanecem pendentes.

---

# Scripts Principais

| Script | Uso |
|---|---|
| `run_child_floorplan.tcl` | floorplan inicial de blocos filhos |
| `run_child_signoff.tcl` | fluxo completo para blocos standard-cell |
| `run_child_macro_route.tcl` | fluxo para blocos com SRAM macro |
| `run_gmp_feature_piped_100m.tcl` | implementação GMP em lanes pipelineadas a 100 MHz |
| `run_mac_core_100m_05.tcl` | hardening do MACcore compatível com a Capture RAM registrada |
| `run_mac_core_100m_05_continue_drt_01.tcl` | continuação do MACcore a partir do global-route |
| `run_capture_*_drc_check.tcl` | auditoria da integração da Capture RAM |
| `run_coef_bank_*_drc_check.tcl` | auditoria da integração do Coef Bank |
| `run_top_corrected_100m.sh` | preparação das views atuais e execução do top conectado |

Os scripts de continuação não alteram constraints para produzir aprovação
artificial. Eles preservam os checkpoints anteriores e repetem apenas a etapa
necessária com os mesmos checks de DRC/LVS.
