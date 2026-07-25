# Implementação HDL

Este diretório contém a versão HDL selecionada para revisão. As versões
intermediárias usadas durante o desenvolvimento foram consolidadas nesta
estrutura para evitar duplicidade. A evolução do projeto é descrita nos textos
de documentação, enquanto a árvore `rtl/` representa o estado atual do hardware.

```text
HDL/
├── rtl/   módulos Verilog do DPD SoC
├── tb/    testbenches SystemVerilog
└── sim/   scripts Questa e vetores pequenos
```

---

# Organização do RTL

O top funcional do DPD é `dpd_top.v`. Ele integra o caminho rápido de inferência
com o caminho lento de captura e treinamento. O `soc_top.v` adiciona PicoRV32,
AXI, UART, SPI e memórias do sistema, mantendo o DPD como periférico controlado.

O caminho rápido é formado principalmente pelo `gmp_engine.v`. Esse bloco
calcula a saída pre-distorcida a partir das amostras I/Q e dos coeficientes
complexos do modelo GMP. O contrato numérico é Q1.15 para amostras e Q2.16 para
coeficientes. A versão HDL funcional é usada nos testbenches, enquanto a versão
OpenLane recebe ajustes físicos específicos dentro de `openlane/`.

O caminho lento usa `capture_ram_pingpong.v` para armazenar snapshots de
referência e feedback. O `mac_engine.v` lê esses dados e executa o treinamento
NLMS. O treinamento não precisa acompanhar a taxa de amostragem de 24 MS/s,
porque trabalha em background com blocos de dados capturados. Essa separação foi
fundamental para controlar área em SKY130.

O `metric_engine.v` calcula métricas simples e sintetizáveis. A escolha por
métricas L1/EWMA foi feita para manter custo lógico baixo e permitir que o
controle detecte degradação do sinal sem implementar medições espectrais caras
em hardware.

---

# Módulos Principais

| Arquivo | Descrição |
|---|---|
| `dpd_top.v` | integração do subsistema DPD |
| `gmp_engine.v` | inferência GMP com 39 termos |
| `mac_engine.v` | treinamento NLMS em background |
| `metric_engine.v` | potência, erro, drift e clipping |
| `capture_ram_pingpong.v` | captura REF/FB com alternância de banco |
| `coef_bank_a.v`, `coef_bank_b.v` | armazenamento de coeficientes |
| `coef_switch_ctrl.v` | troca sincronizada de banco |
| `axi_lite_regs.v` | registradores de controle e status |
| `soc_top.v` | integração com PicoRV32 e periféricos |

---

# Testes de Simulação

A validação foi construída em etapas. Os primeiros testbenches verificam UART,
SPI, AXI-Lite, RAM, atraso de alinhamento, bancos de coeficientes e controle de
troca. Depois foram adicionados testes específicos para os blocos críticos:
`GMPengine`, `MetricEngine` e `MACcore`.

Os testes finais de integração estão em:

```text
sim/run_dpd_top_full_system.do
sim/run_dpd_top_gmp_metric_integration.do
sim/run_dpd_top_internal_train_full_gmp.do
sim/run_mac_engine_nlms.do
```

O teste `run_dpd_top_full_system.do` reproduz a sequência operacional completa:
bypass inicial, captura, treinamento, atualização do banco de coeficientes,
troca sincronizada, DPD ativo, cálculo de métricas e solicitação de novo
treinamento.

---

# Observação de Timing

Na versão física do `GMPengine` preparada para OpenLane, a inferência foi
serializada em quatro fases para reduzir área. Isso significa que, em modo DPD
ativo, o bloco aceita uma nova amostra a cada quatro ciclos. Para uma taxa de
24 MS/s, o clock mínimo é:

```text
24 MS/s x 4 = 96 MHz
```

O fechamento físico preliminar indicou aproximadamente 90,9 MHz. O HDL
funcional está coerente, mas a implementação física ainda precisa de otimização
de timing ou redução do intervalo de iniciação para garantir margem.
