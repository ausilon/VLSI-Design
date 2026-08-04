# DPD SoC v3 - Planejamento OpenLane/SKY130

Data: 2026-07-11.

Objetivo desta versao:

- Preparar a transicao do RTL validado em Questa para avaliacao fisica em
  OpenLane/SKY130.
- Manter o RTL original em `/home/Ausilon/Desktop/dpd_v1/dpd_soc_min/rtl_v2`.
- Criar um snapshot separado para OpenLane em
  `/home/Ausilon/openlane_work/designs/dpd_soc_min`.
- Comecar por sintese/floorplan do subsistema `dpd_top`, antes de tentar o SoC
  completo com PicoRV32.

## Estado de entrada

Blocos criticos ja validados em simulacao:

- `gmp_engine`: inferencia GMP complexa, 39 termos, Q1.15 samples, Q2.16
  coeficientes, pipeline com throughput de 1 amostra/ciclo apos load.
- `metric_engine`: metricas L1/EWMA de potencia, erro REF-FB, clipping e drift,
  com `retrain_request` por thresholds.
- `mac_engine`: treino interno block NLMS da mesma base GMP de 39 termos,
  `NLMS_MAX_EPOCHS=20`, `NLMS_MIN_EPOCHS=10`, `NLMS_MU_SHIFT=2`.

Teste integrado validado:

```text
boot em bypass -> capture -> treino -> banco B -> DPD ativo
-> metricas disparam retreino -> nova captura -> treino banco A
-> switch sincronizado de volta para banco A
```

Resultado:

```text
[TB PASS] tb_dpd_top_full_system
```

## Snapshot OpenLane criado

Projeto:

```text
/home/Ausilon/openlane_work/designs/dpd_soc_min
```

Arquivos principais:

```text
config.json
pin_order.cfg
src/*.v
doc/SNAPSHOT.md
```

Origem do RTL:

```text
/home/Ausilon/Desktop/dpd_v1/dpd_soc_min/rtl_v2
```

Destino do RTL:

```text
/home/Ausilon/openlane_work/designs/dpd_soc_min/src
```

Top inicial:

```text
dpd_top
```

Motivo: `dpd_top` contem o datapath DPD, bancos de coeficientes, captura,
metricas e MACcore. O `soc_top` com PicoRV32 deve ser etapa posterior, pois
mistura firmware, interconnect, SPI flash, RAM e perifericos que podem mascarar
os gargalos fisicos do DPD.

## Configuracao inicial

Arquivo:

```text
/home/Ausilon/openlane_work/designs/dpd_soc_min/config.json
```

Parametros iniciais:

- `DESIGN_NAME = dpd_top`
- `CLOCK_PORT = clk`
- `CLOCK_PERIOD = 20 ns`
- frequencia inicial equivalente: `50 MHz`
- `FP_CORE_UTIL = 30`
- `PL_TARGET_DENSITY = 0.45`
- standard cell inicial: `sky130_fd_sc_hd`

Justificativa:

- O datapath foi validado para operar funcionalmente a 24 Msps.
- Como o `gmp_engine` aceita 1 amostra/ciclo, 24 MHz seria o minimo funcional.
- Comecar com 50 MHz cria margem para timing sem ser agressivo demais para o
  primeiro run.
- Utilizacao de 30% evita congestionamento inicial enquanto ainda nao sabemos
  a area real do `mac_engine` e dos acumuladores.

## Passo 1 - Sanity check de sintese

Objetivo:

- Verificar se o RTL atual e aceito pelo Yosys/OpenLane.
- Identificar problemas de inferencia de memoria, arrays, multiplicadores,
  divisoes sequenciais, largura de acumuladores e constructs Verilog.

Comando previsto:

```bash
cd /home/Ausilon/OpenLane
./flow.tcl -design /home/Ausilon/openlane_work/designs/dpd_soc_min -tag synth_sanity_01 -overwrite
```

Se quisermos entrar no container primeiro:

```bash
/home/Ausilon/openlane_work/openlane_shell.sh
```

Depois, dentro do ambiente OpenLane:

```bash
./flow.tcl -design /home/Ausilon/openlane_work/designs/dpd_soc_min -tag synth_sanity_01 -overwrite
```

O que observar:

- erro de elaboracao/sintese;
- numero de celulas;
- numero de flops;
- inferencia de multiplicadores;
- inferencia de memorias;
- warnings sobre latches;
- fanout alto;
- caminho critico estimado apos sintese.

## Passo 2 - Escolha do primeiro alvo fisico

Temos tres opcoes:

### Opcao A - `dpd_top`

Inclui:

- fast path;
- capture RAM;
- metricas;
- MACcore;
- AXI-Lite regs;
- bancos A/B.

Vantagem:

- valida a integracao real do DPD.

Risco:

- pode ficar grande, especialmente por `mac_engine`, arrays e multiplicadores.

### Opcao B - `gmp_engine`

Vantagem:

- foca no caminho critico de 24 Msps;
- melhor para timing inicial.

Risco:

- nao mede area total do sistema.

### Opcao C - `mac_engine`

Vantagem:

- mede o bloco com maior risco de area.

Risco:

- timing nao representa o fast path; e um bloco lento.

Recomendacao atual:

1. tentar `dpd_top` para sintese exploratoria;
2. se falhar ou ficar grande demais, isolar `gmp_engine` e `mac_engine`;
3. so depois integrar `soc_top`.

## Passo 3 - Floorplan inicial

Parametros a discutir apos a primeira sintese:

- area minima do core;
- `FP_CORE_UTIL`;
- `PL_TARGET_DENSITY`;
- posicao dos pinos;
- separacao entre AXI/control path e I/Q datapath;
- necessidade de macro/memoria dedicada para capture RAM e bancos de
  coeficientes.

Hipotese inicial:

- pinos de amostra e feedback no norte/sul;
- AXI-Lite em leste/oeste;
- `clk`, `resetn` e `sync_event` no oeste;
- saida I/Q no sul.

Arquivo provisório:

```text
/home/Ausilon/openlane_work/designs/dpd_soc_min/pin_order.cfg
```

## Passo 4 - Pontos de risco para SKY130

Riscos principais:

- `gmp_engine`: muitos produtos/acumulacoes por ciclo.
- `mac_engine`: 39 termos, divisores sequenciais, acumuladores de 64/80 bits.
- RAMs inferidas: capture RAM ping-pong e bancos de coeficientes podem virar
  muitos flops se nao forem mapeados para memoria adequada.
- `isqrt32`: raiz inteira pode pesar em area/timing.
- Fanout de controle: sinais globais como `enable`, `force_bypass`,
  `sync_event`, `active_bank`.

Mitigacoes provaveis:

- reduzir clock alvo inicialmente;
- sintetizar blocos isolados;
- substituir RAM inferida por macros SRAM quando necessario;
- serializar mais o MACcore se area explodir;
- revisar `isqrt32` para aproximacao L1/LUT se timing ficar ruim;
- criar wrappers menores para OpenLane.

## Passo 5 - Checks esperados por etapa

Sintese:

- `Yosys` completa sem erro;
- sem latch inesperado;
- area em celulas plausivel;
- timing pos-sintese com WNS aceitavel ou pelo menos diagnosticavel.

Floorplan:

- core nao congestionado;
- pinos posicionados sem conflito;
- PDN gerado;
- sem erro de tap/decap.

Placement:

- densidade aceitavel;
- sem overflow severo;
- fanout/timing analisavel.

CTS:

- clock tree gerada;
- skew dentro do esperado;
- sem buffers absurdos.

Routing:

- sem DRC critico;
- sem congestionamento irrecuperavel;
- timing pos-route documentado.

Signoff:

- DRC;
- LVS;
- antenna;
- STA.

## Comandos uteis

Entrar no shell OpenLane:

```bash
/home/Ausilon/openlane_work/openlane_shell.sh
```

Rodar o design DPD:

```bash
cd /home/Ausilon/OpenLane
./flow.tcl -design /home/Ausilon/openlane_work/designs/dpd_soc_min -tag run_dpd_top_01 -overwrite
```

Listar runs:

```bash
ls -la /home/Ausilon/openlane_work/designs/dpd_soc_min/runs
```

## Decisoes pendentes antes do primeiro run serio

- Clock alvo inicial: manter `20 ns / 50 MHz` ou testar `41.67 ns / 24 MHz`.
- Rodar primeiro `dpd_top` completo ou bloco isolado `gmp_engine`.
- Manter `mac_engine` dentro do primeiro floorplan ou criar build separado.
- Aceitar RAM inferida na primeira rodada ou preparar macros SRAM.
- Definir se AXI-Lite entra no primeiro ASIC block ou se sera substituido por
  interface menor para caracterizacao de area.

## Proximo passo

Discutir os detalhes de sintese e floorplan antes de executar OpenLane:

1. definir top de primeira sintese;
2. definir clock;
3. definir se vamos usar RAM inferida ou macro;
4. definir utilizacao inicial;
5. rodar `synth_sanity_01`;
6. analisar relatorios antes de placement completo.

## Decisao 2026-07-11 - Primeiro alvo OpenLane

Decisao:

- Comecar pelo `gmp_engine`, nao pelo `dpd_top`.
- Clock alvo inicial: `100 MHz`, equivalente a `CLOCK_PERIOD = 10 ns`.
- Usar wrapper registrado para entradas e saidas.

Motivo:

- O `gmp_engine` e o bloco mais critico para throughput.
- Ele e o bloco que precisa sustentar o fast path.
- Ja possui pipeline interno, entao 100 MHz e uma meta razoavel para avaliar
  margem sobre 24 Msps.
- Isolar o bloco evita que AXI-Lite, capture RAM, MACcore e controle poluam a
  primeira analise de timing.

Projeto criado:

```text
/home/Ausilon/openlane_work/designs/dpd_gmp_engine_100m
```

Arquivos:

```text
config.json
pin_order.cfg
src/gmp_engine.v
src/gmp_engine_ol_wrapper.v
doc/SNAPSHOT.md
```

Top OpenLane:

```text
gmp_engine_ol_wrapper
```

Comando previsto:

```bash
cd /home/Ausilon/OpenLane
./flow.tcl -design /home/Ausilon/openlane_work/designs/dpd_gmp_engine_100m -tag run_gmp_100m_01 -overwrite
```

Pontos a observar no primeiro run:

- se o `isqrt32` vira caminho critico;
- se os grupos de acumulacao `0..9`, `10..19`, `20..29`, `30..38` fecham em
  10 ns;
- area em celulas do fast path;
- quantidade de multiplicadores sintetizados;
- necessidade de quebrar os grupos de 10 termos em mais estagios;
- WNS/TNS apos sintese, placement e route.

## Resultado parcial - `run_gmp_100m_01`

Comando executado no container OpenLane:

```bash
docker run --rm \
  -v /home/Ausilon/OpenLane:/openlane \
  -v /home/Ausilon/OpenLane/designs:/openlane/install \
  -v /home/Ausilon:/home/Ausilon \
  -v /home/Ausilon/.ciel:/home/Ausilon/.ciel \
  -e PDK_ROOT=/home/Ausilon/.ciel \
  -e PDK=sky130A \
  -e PWD=/openlane \
  -w /openlane \
  ghcr.io/the-openroad-project/openlane:ff5509f65b17bfa4068d5336495ab1718987ff69-amd64 \
  ./flow.tcl -design /home/Ausilon/openlane_work/designs/dpd_gmp_engine_100m \
  -tag run_gmp_100m_01 -overwrite
```

Primeiro erro encontrado:

- O Yosys nao aceitava a funcao `isqrt32` original com `while` dependente de
  valor dinamico:
  `Function \isqrt32 can only be called with constant arguments`.

Correcao aplicada:

- `isqrt32` foi reescrita com loops `for` de 16 iteracoes fixas.
- A funcao foi marcada como `automatic` para preservar o comportamento em
  chamadas multiplas dentro do mesmo ciclo.
- A mudanca foi aplicada em:
  `/home/Ausilon/Desktop/dpd_v1/dpd_soc_min/rtl_v2/gmp_engine.v`
  e nos snapshots OpenLane.

Validacao apos correcao:

- `vlog` do `gmp_engine` e do wrapper: 0 erros, 0 warnings.
- `tb_gmp_engine_opendpd` foi reexecutado em modo silencioso e retornou codigo
  0 apos a correcao `automatic`.

Segundo resultado:

- O linter OpenLane passou com 0 erros e 23 warnings.
- A sintese avancou ate o ABC.
- Antes do ABC, o Yosys reportou aproximadamente:

```text
Number of cells: 678532
Extracted 675702 gates and 678493 wires
inputs: 2789
outputs: 2736
```

Conclusao:

- O `gmp_engine` atual e funcional, mas esta grande demais para uma iteracao
  OpenLane agil em 100 MHz.
- O gargalo provavel e a combinacao de:
  `isqrt32`, calculo de magnitude, multiplos produtos Q15/Q2.16 e grupos de
  acumulacao de ate 10 termos por estagio.
- O run foi interrompido durante o ABC para nao prender a maquina por tempo
  excessivo.

Proximo ajuste recomendado antes de novo run:

1. criar variante `gmp_engine_area_timing_v2`;
2. substituir `sqrt(I^2+Q^2)` por aproximacao sintetizavel mais barata, por
   exemplo magnitude L1 ou max-plus-min:
   `mag ~= max(abs(I),abs(Q)) + (min(abs(I),abs(Q)) >> 1)`;
3. reduzir os grupos de acumulacao de 10 termos para grupos menores, com mais
   estagios de pipeline;
4. rerodar OpenLane primeiro em `CLOCK_PERIOD=20 ns`;
5. depois retornar para `10 ns` se a area e o ABC ficarem trataveis.

## Iteracao cautelosa - serializacao OpenLane apenas

Diretriz adotada nesta iteracao:

- nao alterar mais a pasta principal do projeto;
- trabalhar somente no RTL copiado para o ambiente OpenLane:
  `/home/Ausilon/openlane_work/designs/dpd_gmp_engine_100m/src/gmp_engine.v`;
- manter a mesma quantizacao Q1.15 para amostras e Q2.16 para coeficientes;
- manter fidelidade com o modelo OpenDPD de 39 termos e coeficientes complexos.

Alteracoes realizadas no snapshot OpenLane:

- `gmp_engine` foi convertido para uma arquitetura serializada em 4 fases;
- a 100 MHz, o contrato passa a aceitar 1 amostra a cada 4 ciclos, ou seja,
  aproximadamente 25 Msps;
- as potencias de amplitude `|x|^2`, `|x|^3` e `|x|^4` passaram a ser
  pre-computadas uma vez por amostra e reutilizadas nos termos GMP;
- a acumulacao foi reorganizada como `phase_acc`, com 10 lanes fisicas
  reutilizadas nas fases 0, 1, 2 e 3.

Validacao funcional:

- `vlog` do snapshot OpenLane: 0 erros, 0 warnings;
- `tb_gmp_engine_opendpd` temporario em `/tmp` passou contra o golden OpenDPD;
- resultado: 64/64 amostras bateram exatamente com os HEX esperados.

Runs OpenLane desta iteracao:

- `run_gmp_serial4_100m_01`: interrompido; ainda havia muita expansao de
  funcoes de potencia/amplitude.
- `run_gmp_serial4_pow_100m_01`: interrompido; reduziu duplicacao de potencia,
  mas o Yosys ainda expandia grupos grandes demais.
- `run_gmp_phase10_100m_01`: melhor resultado ate aqui.

Resultado pre-ABC do `run_gmp_phase10_100m_01`:

```text
Number of cells: 193695
Extracted gates before ABC: 191186
DFFs mapped to SKY130: 2509
```

Comparacao direta:

- versao paralela inicial: ~678k celulas antes do ABC;
- versao serializada em 4 fases: ~194k celulas antes do ABC;
- reducao aproximada: 71%;
- meta inicial de ficar abaixo de 300k celulas foi atingida nesta etapa.

Observacao critica:

- o ABC ainda ficou pesado e foi interrompido depois de aproximadamente 1 hora;
- o gargalo restante e o mapeamento tecnologico dos multiplicadores grandes e
  muxes de coeficientes;
- para PnR completo, o proximo ajuste deve mirar multiplicadores mais trataveis,
  sem alterar a precisao numerica validada contra o golden.

## Iteracao MACcore serializado - alvo de treino abaixo de 5 minutos

Diretriz:

- manter a pasta principal sem novas alteracoes;
- alterar apenas o RTL copiado no ambiente OpenLane:
  `/home/Ausilon/openlane_work/designs/dpd_soc_min/src/mac_engine.v`;
- criar alvo isolado para sintese:
  `/home/Ausilon/openlane_work/designs/dpd_mac_engine_100m`.

Arquitetura adotada:

- MACcore maximamente serializado;
- 39 termos GMP preservados;
- coeficientes complexos Q2.16 preservados;
- amostras Q1.15 preservadas;
- um termo de base GMP calculado por ciclo;
- por amostra valida:
  - aproximadamente 39 ciclos para acumular o modelo atual;
  - aproximadamente 39 ciclos para acumular gradiente/energia NLMS;
  - overhead de leitura/controle;
- divisao NLMS continua serial por bit.

Estimativa de tempo:

- 1024 amostras, 20 epocas, ~80 ciclos por amostra:
  ~1,64 milhao de ciclos;
- a 100 MHz: ~16,4 ms para varredura das amostras;
- overhead de divisao/atualizacao dos 39 coeficientes fica muito abaixo de 5
  minutos;
- portanto a meta de treinamento completo abaixo de 5 minutos tem muita folga.

Validacao funcional inicial:

- compilacao Questa do `mac_engine` serializado: 0 erros, 0 warnings;
- `tb_mac_engine_manual` legado:
  - treino inicia, trava captura, termina sem `train_error`;
  - `coef_ready` e `capture_release` sobem;
  - escreve os 78 words de coeficiente;
  - `status_error_acc` permanece na faixa esperada;
  - duas expectativas numericas estreitas do TB antigo falham:
    `coef2_imag` fica fora da janela +/-512 e `coef38_imag` fica em -1.

Diagnostico da diferenca numerica:

- foi criado um testbench temporario em `/tmp` comparando a versao paralela
  salva em `doc/mac_engine_parallel_ref.vtxt` contra a versao serial;
- primeira epoca:
  - `acc_num_real[2] = 7980000`;
  - `acc_num_imag[2] = 0`;
  - `acc_den[2] = 15960000`;
  - `epoch_model_error_acc = 3700`;
  - as duas versoes batem exatamente;
- a divergencia aparece a partir da epoca 1, quando a versao serial passa a
  calcular o modelo residual completo termo a termo;
- a expectativa antiga de `coef2_imag` pequeno nao era um bom criterio para este
  caso, pois 4 amostras contra 39 termos complexos deixam o problema
  subdeterminado;
- foi criado um testbench permanente no alvo OpenLane para congelar os
  checkpoints corretos do RTL serializado:
  `/home/Ausilon/openlane_work/designs/dpd_mac_engine_100m/tb/tb_mac_engine_serial_golden.sv`;
- tambem foi criado um `.do` para abrir no Questa:
  `/home/Ausilon/openlane_work/designs/dpd_mac_engine_100m/sim/run_mac_engine_serial_golden.do`;
- o TB novo valida:
  - primeira epoca: acumuladores NLMS do termo 2;
  - final do treino: `coef2=(2225,-2119)`;
  - final do treino: `coef38_imag=-1`;
  - `status_error_acc=99000`;
  - escrita completa dos 78 words de coeficiente.

```text
[EPOCH0] acc2_real=7980000 acc2_imag=0 den2=15960000 model_error=3700
[GOLDEN] coef2=(2225,-2119) coef38_imag=-1 status_error_acc=99000 writes=78
[TB PASS] tb_mac_engine_serial_golden
```

Comando validado:

```bash
/home/Ausilon/intelFPGA_standard/24.1std/questa_fse/linux_x86_64/vsim -c -do /home/Ausilon/openlane_work/designs/dpd_mac_engine_100m/sim/run_mac_engine_serial_golden.do
```

Resultado: 0 erros. O unico warning vem do `+acc`, usado de proposito para
abrir sinais internos na waveform.

Conclusao tecnica:

- a diferenca numerica nao indica erro da serializacao;
- a correcao foi no metodo de validacao, nao nos calculos do RTL serializado;
- o `tb_mac_engine_manual` legado e fraco para validar 39 termos com apenas 4
  amostras, pois o problema fica subdeterminado e permite overfitting;
- a versao paralela antiga tambem nao deve ser usada como golden estrito,
  porque possui multiplas funcoes Verilog nao-`automatic` chamadas de forma
  concorrente dentro de funcoes maiores;
- o proximo golden mais forte deve usar dataset maior e, idealmente, um modelo
  software bit-compativel com as escolhas exatas de arredondamento/saturacao do
  RTL.

Resultado OpenLane isolado - `run_mac_serial_100m_02`:

```text
Pre-ABC:
Number of cells: 105169

Depois do DFFLIBMAP:
Number of cells: 116489
sky130_fd_sc_hd__dfrtp_2: 11265
sky130_fd_sc_hd__dfstp_2: 64
Extracted gates before ABC: 105160
```

Comparacao preliminar:

- GMP serializado: ~193,7k celulas antes do ABC final;
- MACcore serializado: ~116,5k celulas antes do ABC final;
- MACcore ficou menor que o GMP nesta arquitetura, como esperado para treino
  lento/background.

Status:

- a rodada foi interrompida no ABC final para nao prender a maquina;

## Iteracao floorplan filhos - preparacao top fisico

Diretriz:

- manter a pasta principal sem novas alteracoes;
- criar projetos-filho dentro de `/home/Ausilon/openlane_work/designs`;
- preparar blocos menores para futura montagem do top fisico conforme o
  desenho conceitual do die;
- usar SRAM macros nos blocos de RAM e coeficientes para evitar memoria
  sintetizada em celulas padrao.

Projetos criados:

- `dpd_pico_100m`: wrapper fisico do PicoRV32;
- `dpd_axi_100m`: interconnect AXI-Lite + registradores DPD;
- `dpd_peripherals_100m`: UART, SPI debug e IRQ/status;
- `dpd_metrics_100m`: metric engine;
- `dpd_coef_bank_macro_100m`: dois bancos de coeficientes usando SRAM macro
  `sky130_sram_1kbyte_1rw1r_32x256_8`;
- `dpd_capture_ram_macro_100m`: capture RAM ping-pong usando oito SRAM macros
  `sky130_sram_2kbyte_1rw1r_32x512_8`.

Script de floorplan:

```bash
CHILD_DESIGN=<design> CHILD_TAG=floorplan_100m_01 \
  ./flow.tcl -interactive -file ./designs/run_child_floorplan.tcl
```

Resultados `floorplan_100m_01`:

```text
dpd_metrics_100m             324.76 x 323.68 um   ~3.7k cells dffmap
dpd_pico_100m                597.54 x 595.68 um   ~10.2k cells dffmap
dpd_peripherals_100m         192.28 x 190.40 um   ~950 cells dffmap
dpd_axi_100m                 759.46 x 756.16 um   ~1.8k cells dffmap
dpd_coef_bank_macro_100m    1219.92 x 568.48 um   2 SRAM macros + glue
dpd_capture_ram_macro_100m  1719.94 x 2216.80 um  8 SRAM macros + glue
```

Artefatos gerados em cada filho:

- `results/synthesis/*.v`;
- `results/synthesis/*.sdf`;
- `results/floorplan/*.def`;
- `results/floorplan/*.odb`.

Observacao:

- ainda nao sao LEFs finais de macro; para isso cada filho precisa completar
  placement/CTS/routing/signoff ou receber tratamento como macro fisico no fluxo
  top-level;
- os wrappers de RAM/coef com SRAM macro sao para planejamento fisico inicial e
  exigem revisao funcional por causa da leitura sincrona das SRAMs, diferente
  das memorias inferidas assíncronas originais.

## Iteracao route/signoff filhos - blocos menores

Ordem adotada:

1. `dpd_peripherals_100m`;
2. `dpd_metrics_100m`;
3. `dpd_pico_100m`;
4. `dpd_axi_100m`;
5. `dpd_coef_bank_macro_100m`;
6. `dpd_capture_ram_macro_100m`.

Blocos standard-cell com signoff completo:

```text
dpd_peripherals_100m  signoff_100m_01  route ok, Magic DRC ok, LVS errors=0, KLayout GDS ok
dpd_metrics_100m      signoff_100m_01  route ok, Magic DRC ok, LVS errors=0, KLayout GDS ok
dpd_pico_100m         signoff_100m_01  route ok, Magic DRC ok, LVS errors=0, KLayout GDS ok
dpd_axi_100m          signoff_100m_01  route ok, Magic DRC ok, LVS errors=0, KLayout GDS ok
```

Artefatos principais:

```text
results/signoff/peripherals_wrapper.lef
results/signoff/peripherals_wrapper.gds
results/signoff/metric_engine.lef
results/signoff/metric_engine.gds
results/signoff/picorv32_ol_wrapper.lef
results/signoff/picorv32_ol_wrapper.gds
results/signoff/axi_ctrl_wrapper.lef
results/signoff/axi_ctrl_wrapper.gds
```

Blocos com SRAM hard macro:

```text
dpd_coef_bank_macro_100m     macro_route_100m_01  route ok, GDS/LEF gerados
dpd_capture_ram_macro_100m   macro_route_100m_01  route ok, GDS/LEF gerados
```

Artefatos principais:

```text
results/signoff/coef_bank_macro.lef
results/signoff/coef_bank_macro.gds
results/signoff/capture_ram_macro.lef
results/signoff/capture_ram_macro.gds
```

Observacao sobre SRAM:

- `coef_bank_macro` e `capture_ram_macro` usam SRAMs do PDK como hard macros;
- o fluxo `macro_route` nao roda Magic DRC/LVS transistor-level dentro das
  SRAMs;
- isso nao ignora falhas do nosso roteamento: detailed route chegou a 0
  violacoes antes da geracao de GDS/LEF;
- a parte assumida como pre-validada e o interior da SRAM macro fornecida pelo
  PDK;
- no top-level ainda devemos validar integracao fisica, pinos, halos, PDN e
  roteamento ao redor das macros.

Script de signoff standard-cell:

```bash
CHILD_DESIGN=<design_name> CHILD_TAG=signoff_100m_01 \
  ./flow.tcl -interactive -file ./designs/run_child_signoff.tcl
```

Script para filhos com SRAM macro:

```bash
CHILD_DESIGN=<design_name> CHILD_TAG=macro_route_100m_01 \
  ./flow.tcl -interactive -file ./designs/run_child_macro_route.tcl
```

Comandos manuais recomendados para os blocos pesados restantes:

```bash
docker run --rm \
  -e PWD=/openlane \
  -e PDK=sky130A \
  -e PDK_ROOT=/pdkroot \
  -e CHILD_DESIGN=dpd_gmp_engine_100m \
  -e CHILD_TAG=signoff_100m_01 \
  -v /home/Ausilon/openlane_work/designs:/openlane/designs \
  -v /home/Ausilon/.ciel/ciel/sky130/versions/0fe599b2afb6708d281543108caf8310912f54af:/pdkroot \
  ghcr.io/the-openroad-project/openlane:ff5509f65b17bfa4068d5336495ab1718987ff69-amd64 \
  bash -lc 'cd /openlane && ./flow.tcl -interactive -file ./designs/run_child_signoff.tcl'
```

```bash
docker run --rm \
  -e PWD=/openlane \
  -e PDK=sky130A \
  -e PDK_ROOT=/pdkroot \
  -e CHILD_DESIGN=dpd_mac_engine_100m \
  -e CHILD_TAG=signoff_100m_01 \
  -v /home/Ausilon/openlane_work/designs:/openlane/designs \
  -v /home/Ausilon/.ciel/ciel/sky130/versions/0fe599b2afb6708d281543108caf8310912f54af:/pdkroot \
  ghcr.io/the-openroad-project/openlane:ff5509f65b17bfa4068d5336495ab1718987ff69-amd64 \
  bash -lc 'cd /openlane && ./flow.tcl -interactive -file ./designs/run_child_signoff.tcl'
```
- os arquivos estao prontos para rodar full em outra maquina.

### GMP 100 MHz - tentativa `signoff_100m_01`

Resultado parcial:

- sintese, floorplan, placement, CTS e otimizacoes pre-route avancaram;
- global routing chegou a congestionamento final com overflow 0;
- o fluxo falhou durante reparo de antena no step 18 (`groute.tcl`);
- o log mostrou reducao das violacoes de antena de 2316 para 5, mas o processo
  foi morto por `kill signal` na iteracao 9;
- isso indica problema de fluxo fisico/recursos durante antenna repair, nao uma
  falha funcional conhecida no HDL do GMP.

Metricas principais da tentativa:

```text
synth_cell_count       328576
DIEAREA_mm2            12.206
CoreArea_um2           12087094.98
wire_length            23031820 um
routed nets            332523
global route overflow  0
violacoes antena       2316 -> 799 -> 134 -> 23 -> 17 -> 8 -> 6 -> 5
```

Ajuste aplicado somente no ambiente OpenLane do GMP:

```json
"RUN_HEURISTIC_DIODE_INSERTION": true,
"HEURISTIC_ANTENNA_INSERTION_MODE": "source",
"HEURISTIC_ANTENNA_THRESHOLD": 60,
"GRT_REPAIR_ANTENNAS": true,
"GRT_ANT_ITERS": 8
```

Objetivo da proxima tentativa:

- inserir diodos de antena mais cedo, antes do roteamento final;
- reduzir a carga do reparo iterativo dentro do global router;
- preservar o HDL e a aritmetica ja validados.

### MAC 100 MHz - estrategia preventiva apos GMP

O GMP mostrou que o fluxo padrao do OpenLane pode consumir muita memoria no
TritonRoute quando filler cells sao inseridas antes do detailed routing. Para o
MACcore, foi criado um fluxo especifico que preserva sintese, placement, CTS e
resizers, mas reordena o backend fisico:

```text
synthesis -> floorplan -> placement -> CTS -> resizers -> diodes/antenna
-> global route -> detailed route -> filler -> Magic/DRC/LVS/KLayout
```

Ajustes aplicados somente em `/home/Ausilon/openlane_work`:

```json
"RUN_HEURISTIC_DIODE_INSERTION": true,
"HEURISTIC_ANTENNA_INSERTION_MODE": "source",
"HEURISTIC_ANTENNA_THRESHOLD": 60,
"GRT_REPAIR_ANTENNAS": true,
"GRT_ANT_ITERS": 8,
"ROUTING_CORES": 1,
"DRT_OPT_ITERS": 16
```

Script:

```text
/openlane/designs/run_mac_signoff_no_prefill.tcl
```

### Top-level macro assembly

Foi criado o design fisico preliminar:

```text
/home/Ausilon/openlane_work/designs/dpd_soc_macro_top_100m
```

Objetivo desta etapa:

- reunir as hard macros geradas;
- aproximar o floorplan do desenho definido para o die;
- gerar uma view GDSII para documentacao/artigo;
- manter esta montagem como macro-level physical assembly, ainda sem fechar
  roteamento funcional completo entre todos os blocos.

Hard macros instanciadas:

```text
metric_engine
picorv32_ol_wrapper
axi_ctrl_wrapper
peripherals_wrapper
gmp_engine_ol_wrapper
capture_ram_macro
coef_bank_macro
mac_engine
```

Dimensao do die top-level preliminar:

```text
7.20 mm x 8.80 mm = 63.36 mm2
Core aproximado: 6.80 mm x 8.40 mm
```

Layout fisico aproximado:

```text
controle/perifericos  lado esquerdo
GMP core              topo direito
capture RAM           centro
coef bank             centro direito
MAC engine            parte inferior direita/central
```

Artefatos gerados:

```text
/home/Ausilon/openlane_work/designs/dpd_soc_macro_top_100m/runs/macro_view_final_01/results/signoff/dpd_soc_macro_top.gds
/home/Ausilon/openlane_work/designs/dpd_soc_macro_top_100m/runs/macro_view_final_01/results/signoff/dpd_soc_macro_top.klayout.gds
/home/Ausilon/openlane_work/designs/dpd_soc_macro_top_100m/runs/macro_view_final_01/results/signoff/dpd_soc_macro_top.lef
/home/Ausilon/openlane_work/designs/dpd_soc_macro_top_100m/dpd_soc_macro_top_floorplan_view.png
/home/Ausilon/Desktop/dpd_v1/dpd_soc_min/docs/dpd_soc_macro_top_floorplan_view.png
```

Observacoes importantes:

- a primeira tentativa top-level falhou no PDN por nos `VPWR` desconectados;
- para gerar a view macro-level, `FP_PDN_CHECK_NODES` e
  `FP_PDN_ENABLE_MACROS_GRID` foram desabilitados no top;
- isso e aceitavel para imagem/floorplan preliminar, mas nao substitui o
  fechamento final de PDN, signal routing, DRC/LVS e pads do chip completo.

### Top-level tapeout scaffold - PDN

Foi criado tambem o projeto:

```text
/home/Ausilon/openlane_work/designs/dpd_soc_tapeout_top_100m
```

A tentativa `tapeout_pdn_check_01` falhou com `PSM-0069` por nos `VPWR`
desconectados na regiao do GMP. A tentativa `tapeout_pdn_check_02` ainda falhou,
mesmo com `FP_PDN_ENABLE_MACROS_GRID=0`, porque o `pdn_cfg.tcl` padrao desta
versao do OpenLane cria grid de macro automaticamente.

Correcao aplicada:

```text
/home/Ausilon/openlane_work/designs/dpd_soc_tapeout_top_100m/pdn_tapeout_cfg.tcl
```

Politica de camadas adotada no top:

```text
met1      rails locais das standard cells
met4      straps verticais de alimentacao
met5      straps horizontais de alimentacao
met4/met5 core ring
```

O grid automatico de macro foi removido no top. As macros continuam usando seus
PDNs internos ja fechados; o top passa a conectar a rede global por straps/ring.

Resultado do checkpoint `tapeout_pdn_check_03`:

```text
All PDN stripes on net VPWR are connected.
All PDN stripes on net VGND are connected.
```

Ainda restam warnings de `VSRC` porque a localizacao real dos power pads/fontes
de alimentacao nao foi declarada. Isso nao e a falha anterior de conectividade,
mas deve ser resolvido antes de tratar o pacote como tapeout final.

### Top-level full flow - resizer

A tentativa `tapeout_full_02` passou por PDN, placement e CTS, mas falhou no
step de routing resizer:

```text
RSZ-0005 Run global_route before estimating parasitics for global routing.
Routed nets: 0
```

Isso ocorre porque o top atual ainda e um scaffold fisico de macros, sem a
conectividade funcional completa entre os blocos. Portanto o OpenROAD encontra
zero nets de sinal para otimizar nessa etapa.

Decisao aplicada:

- pular `run_resizer_design_routing`;
- pular `run_resizer_timing_routing`;
- continuar a partir do checkpoint de CTS usando:

```text
/home/Ausilon/openlane_work/designs/run_tapeout_continue_after_cts_no_resizer.tcl
```

Wrapper:

```bash
cd /home/Ausilon/openlane_work
./designs/dpd_soc_tapeout_top_100m/scripts/continue_after_cts_no_resizer.sh tapeout_full_02
```

### Resultado `tapeout_full_03`

Foi executado um fluxo macro-level corrigido:

- resizers de roteamento desabilitados;
- reparo heuristico de antena desabilitado;
- detailed routing desabilitado porque o top atual gera zero signal guides;
- Magic gerou GDS/LEF/SPICE;
- Magic DRC passou sem violacoes.

Resultado principal:

```text
No DRC violations after GDS streaming out.
LVS total errors = 35
```

Resumo do LVS:

```text
net count difference = 16
device count difference = 0
unmatched nets = 3
unmatched devices = 16
unmatched pins = 0
property failures = 0
```

Artefatos gerados:

```text
/home/Ausilon/openlane_work/designs/dpd_soc_tapeout_top_100m/runs/tapeout_full_03/results/signoff/dpd_soc_tapeout_top.gds
/home/Ausilon/openlane_work/designs/dpd_soc_tapeout_top_100m/runs/tapeout_full_03/results/signoff/dpd_soc_tapeout_top.klayout.gds
/home/Ausilon/openlane_work/designs/dpd_soc_tapeout_top_100m/runs/tapeout_full_03/results/signoff/dpd_soc_tapeout_top.lef
/home/Ausilon/openlane_work/designs/dpd_soc_tapeout_top_100m/runs/tapeout_full_03/results/signoff/dpd_soc_tapeout_top.spice
```

Conclusao tecnica: este GDS e valido para revisao fisica de floorplan/area e
documentacao, mas ainda nao e um chip funcional pronto para foundry. Para virar
tapeout real, o proximo passo e criar o top funcional conectado com padframe,
reativar DRT/antena/LVS/STA e fechar signoff completo.

### Evolução da síntese e implementação física

A comparacao foi nivelada no ultimo checkpoint comum comprovado para as oito
macros: sintese mapeada, CTS, global routing e STA single-corner pos-global-route
com periodo-alvo de 10 ns. As areas usam o `SIZE` dos LEFs correspondentes, as
contagens e a celula dominante vem dos relatorios
`1-synthesis*.stat.rpt`, e os slacks foram lidos nos logs `grt_sta`.

| Macro | Run auditado | Células | Área macro (mm²) | Setup pós-GRT (ns) | Hold pós-GRT (ns) | Dominante Cell |
|---|---|---:|---:|---:|---:|---|
| PicoRV32 | `signoff_100m_01` | 10.114 | 0,377 | +3,41 | +0,15 | `sky130_fd_sc_hd__buf_1` (2.422) |
| AXI control | `signoff_100m_01` | 1.713 | 0,640 | +3,58 | +0,21 | `sky130_fd_sc_hd__buf_1` (395) |
| Peripherals | `signoff_100m_01` | 755 | 0,044 | +4,21 | +0,19 | `sky130_fd_sc_hd__dfrtp_2` (183) |
| MetricEngine | `signoff_100m_01` | 2.593 | 0,116 | +2,94 | +0,24 | `sky130_fd_sc_hd__nand2_2` (272) |
| Capture RAM | `capture_ram_signoff_100m_13` | 741 (inclui 8 SRAM) | 4,140 | +3,93 | +0,26 | `sky130_fd_sc_hd__dfxtp_2` (320) |
| Coef Bank | `coef_bank_signoff_100m_04` | 154 (inclui 2 SRAM) | 0,845 | +1,84 | +1,65 | `sky130_fd_sc_hd__buf_1` (56) |
| GMPengine | `gmp_feature_piped_route_relaxed_100m_01` | 223.170 | 11,497 | +3,16 | +0,09 | `sky130_fd_sc_hd__nand2_2` (79.930) |
| MACcore | `mac_core_100m_05` | 131.048 | 7,758 | +1,47 | +0,16 | `sky130_fd_sc_hd__nand2_2` (35.921) |

A area acumulada dos oito contornos de macro e 25,418 mm2. Esse valor nao
inclui canais entre macros, halos, padframe nem a margem de roteamento do top.
Os slacks positivos descrevem somente os caminhos restritos nesse checkpoint;
nao equivalem a STA RCX multicorner nem permitem declarar Fmax ou signoff.

### Integração física experimental

| Item | Resultado |
|---|---:|
| Clock-alvo | 50 MHz |
| Celulas de integracao | 63.320 |
| Die | 9,3 x 9,3 mm = 86,49 mm2 |
| Setup/hold pos-GRT | +6,97 / +0,02 ns |
| RCX multicorner nominal | -3,11 / -1,46 ns |
| Pior RCX multicorner | -4,74 / -1,82 ns |
| Detailed routing | 0 violacoes |
| GDSII | Gerado |

O `top_v4_clean_50m_01` e um run inicial de integracao destinado a gerar
floorplan, roteamento, SPEF, relatorios STA RCX e GDSII para as analises
posteriores. Esses artefatos orientam o reposicionamento, as restricoes e as
proximas iteracoes ate a evolucao posterior do signoff; o run nao e apresentado
como circuito fechado para fabricacao.

Todas as oito macros possuem uma baseline comparavel no checkpoint
pos-global-route. Resultados adicionais de detailed route, DRC, LVS e XOR
permanecem como evidencias individuais e nao sao usados para elevar
seletivamente o nivel de uma linha da tabela. Da mesma forma, nao se declara
Fmax a partir de WNS intermediario: a frequencia de operacao sera consolidada
somente depois de completar constraints e STA extraido multicorner na baseline
fisica aprovada ou no chip completo.

## Auditoria 2026-08-03 - goldens das revisoes OpenLane

A revisao final da documentacao distinguiu duas linhas de RTL que nao devem ser
tratadas como o mesmo artefato: a implementacao funcional em `HDL/rtl` e as
implementacoes serializadas, preparadas para sintese fisica, em `openlane/`.

Antes da serializacao fisica, a integracao conjunta ja havia sido executada no
`simv2` sobre o `rtl_v2`. Em 2026-07-10, o
`tb_dpd_top_gmp_metric_integration` escreveu 78 palavras Q2.16 no banco A,
comparou 64 saidas do top contra o golden OpenDPD e leu as metricas integradas.
Em 2026-07-11, o `tb_dpd_top_full_system` percorreu:

```text
bypass -> captura -> treino NLMS -> banco B -> troca sincronizada
-> DPD ativo -> metricas/IRQ -> nova captura -> retreino no banco A -> troca
```

Os dois testes foram registrados com `TB PASS`; o teste full-system terminou
com zero erros e zero warnings. Portanto, RAM, bancos, GMPengine, MACcore e
MetricEngine possuem validacao conjunta na revisao funcional.

Os dois blocos DSP criticos possuem validacao golden independente na revisao
usada pelo OpenLane. A limitacao restante e de integracao/regressao conjunta e
de fechamento fisico, nao de ausencia de referencia numerica nos motores.

O `GMPengine` fisico foi recompilado com `gmp_mac_lane.v` e
`isqrt32_pipe.v` e reexecutado no Questa contra os coeficientes Q2.16 e vetores
OpenDPD preservados. Com `enable=1` e flush suficiente para a pipeline de
features/lanes, as 64 saidas I/Q coincidiram bit a bit:

```text
[AUDIT] inputs=66 outputs=64 extra_flush=7 cycles=366
[TB PASS] tb_gmp_engine_opendpd_openlane
Errors: 0, Warnings: 0
```

A falha produzida pelo TB historico na revisao atual foi localizada no proprio
contrato de teste: `enable=0` selecionava bypass e as duas amostras de
lookahead nao drenavam toda a pipeline fisica. O teste reproduzivel da variante
OpenLane foi separado em:

```text
openlane/dpd_gmp_engine_100m/tb/tb_gmp_engine_opendpd_openlane.sv
openlane/dpd_gmp_engine_100m/sim/run_gmp_engine_opendpd.do
```

O `MACcore` serializado tambem foi recompilado e reexecutado contra o golden
NLMS de software. Foram confirmados os acumuladores da primeira epoca, a escrita
das 78 palavras de coeficientes, o melhor modelo e os valores finais:

```text
[GOLDEN] coef2=(2225,-2119) coef38_imag=-1 status_error_acc=99000 writes=78
[TB PASS] tb_mac_engine_serial_golden
Errors: 0, Warnings: 0
```

Esses resultados fecham a equivalencia numerica isolada dos motores fisicos.
A pendencia nao e criar do zero uma regressao conjunta, mas portar a regressao
ja aprovada no `simv2` para um top que instancie essas mesmas revisoes OpenLane
e os contratos atuais de RAM, bancos e metricas.
