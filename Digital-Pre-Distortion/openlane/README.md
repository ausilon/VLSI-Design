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

Essa revisão física foi revalidada no Questa em 2026-08-03: 64 saídas I/Q
coincidiram bit a bit com o golden OpenDPD. O teste mantém `enable=1` e acrescenta
sete amostras nulas após o vetor de 64 amostras úteis e duas de lookahead para
drenar a pipeline física completa.

A integração conjunta com Capture RAM, bancos A/B, treinamento e métricas já
passou no `simv2` usando o `rtl_v2`. Essa evidência não deve ser confundida com
uma regressão do top físico: essa composição com as revisões serializadas exatas
do GMPengine e do MACcore não está presente nesta baseline.

O `MACcore` é maior que um bloco de controle comum, mas não precisa operar na
taxa de amostragem. Ele lê snapshots da RAM e executa treinamento em background.
Por isso, a arquitetura foi mais serializada, privilegiando redução de área em
vez de latência mínima.

---

# Resultado Atual

Para evitar comparar estágios físicos diferentes, os oito blocos são nivelados
no checkpoint comum de STA single-corner pós-global-route com período-alvo de
10 ns. A tabela auditada, incluindo células dominantes, áreas e slacks, está em
[FLOORPLAN_CHILDREN_SUMMARY.md](FLOORPLAN_CHILDREN_SUMMARY.md).

PicoRV32, AXI-Lite, MetricEngine, periféricos, memórias e motores DSP possuem
artefatos físicos posteriores em diferentes graus de maturidade. Esses
resultados continuam úteis para engenharia, mas não são misturados na tabela
como se todos representassem STA RCX, DRC, LVS e signoff equivalentes. Também
não se declara Fmax a partir de WNS intermediário; a baseline não possui
constraints e STA extraído multicorner uniformes que sustentem essa declaração.

A baseline publicada mantém o alvo de 100 MHz. As oito macros possuem resultados
comparáveis no checkpoint pós-global-route, mas as tentativas do top-level não
fecharam STA RCX multicorner de forma uniforme. Por isso, resultados obtidos com
outros períodos de clock não são usados nesta baseline e não se declara uma
frequência final para o chip. O top também não inclui padframe, análise de
potência, IR drop ou signoff físico completo.

---

# Scripts Principais

| Script | Uso |
|---|---|
| `run_child_floorplan.tcl` | floorplan inicial de blocos filhos |
| `run_child_signoff.tcl` | fluxo completo para blocos standard-cell |
| `run_child_macro_route.tcl` | fluxo para blocos com SRAM macro |
| `run_gmp_feature_piped_100m.tcl` | implementação GMP em lanes pipelineadas a 100 MHz |
| `dpd_gmp_engine_100m/sim/run_gmp_engine_opendpd.do` | regressão bit-exata da revisão física contra o golden OpenDPD |
| `run_mac_core_100m_05.tcl` | hardening do MACcore compatível com a Capture RAM registrada |
| `run_mac_core_100m_05_continue_drt_01.tcl` | continuação do MACcore a partir do global-route |
| `run_capture_*_drc_check.tcl` | auditoria da integração da Capture RAM |
| `run_coef_bank_*_drc_check.tcl` | auditoria da integração do Coef Bank |
| `run_top_corrected_100m.sh` | preparação das views atuais e execução do top conectado |

Os scripts de continuação não alteram constraints para produzir aprovação
artificial. Eles preservam os checkpoints anteriores e repetem apenas a etapa
necessária com os mesmos checks de DRC/LVS.
