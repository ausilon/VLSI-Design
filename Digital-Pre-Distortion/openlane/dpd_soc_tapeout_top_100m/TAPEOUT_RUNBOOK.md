# DPD SoC Top-Level Runbook

Este diretório reúne os arquivos de projeto do top hierárquico para OpenLane e
SKY130. Os oito blocos abaixo entram como hard macros:

- `gmp_engine_ol_wrapper`;
- `mac_engine`;
- `capture_ram_macro`;
- `coef_bank_macro`;
- `picorv32_ol_wrapper`;
- `axi_ctrl_wrapper`;
- `metric_engine`;
- `peripherals_wrapper`.

O top contém conectividade funcional. Ele não é apenas uma montagem visual de
macros. FIFOs elásticas desacoplam fronteiras críticas, AXI-Lite permanece
interno e o plano externo expõe os três barramentos I/Q, handshakes, flash SPI,
UART, clock e reset.

## Pré-requisitos

Antes do top, devem existir as views coerentes de cada macro. Em particular:

```text
MACcore:      mac_core_100m_05
Capture RAM:  capture_ram_signoff_100m_13
Coef Bank:    coef_bank_signoff_100m_04
```

O script `prepare_corrected_macro_views.sh` valida a existência das views e
instala os LEF/LIB atuais em `lef_top/` e `lib_top/`. Esses diretórios contêm
artefatos gerados localmente e não são versionados.

## Execução

```bash
cd /home/Ausilon/openlane_work

./designs/dpd_soc_tapeout_top_100m/scripts/run_top_corrected_100m.sh \
  top_v4_memfix_100m_01
```

Monitoramento:

```bash
watch -n 30 \
  '/home/Ausilon/openlane_work/designs/dpd_soc_tapeout_top_100m/scripts/monitor_tapeout.sh top_v4_memfix_100m_01'
```

O launcher recusa sobrescrever um run existente e interrompe antes do OpenLane
se alguma view estiver ausente ou vazia.

## Floorplan e PDN

O die de trabalho mede `8,5 x 8,5 mm`, com core entre `(600,600)` e
`(7900,7900)` micrômetros. A distribuição aproxima Capture RAM e Coef Bank dos
dois motores DSP e mantém PicoRV32, AXI-Lite e periféricos na ilha de controle.

A PDN usa:

- rails de células em met1;
- straps verticais em met4;
- straps horizontais em met5;
- core ring em met4/met5;
- grids de macro e conexões globais `VPWR/VGND` habilitados.

O check `check_macro_pg.tcl` exige que os terminais de alimentação das oito
macros estejam conectados nominalmente a `VPWR` e `VGND`.

## Pinout planejado

O contrato lógico prevê 128 terminais:

| Grupo | Terminais |
|---|---:|
| REF/FB/OUT I/Q | 96 |
| Clock, reset e handshakes | 6 |
| Flash SPI | 4 |
| UART | 2 |
| Reserva DFT | 4 |
| Alimentação e terra | 16 |
| **Total** | **128** |

O alvo provisório é `aQFN/DRQFN-128`, com exposed pad em `VSSD/GND`. O
padframe físico, células ESD/clamp, corners, fillers e bonding diagram ainda
dependem da seleção final do package outline.

## Critérios de aprovação

`check_top_signoff.py` exige:

- artefatos GDS, LEF, LIB, SDF e SPICE presentes;
- setup e hold não negativos nos relatórios RCX disponíveis;
- zero violações de slew e capacitância;
- TritonRoute DRC vazio;
- relatório de antena vazio;
- LVS com `Total errors = 0`;
- métricas finais sem DRC, antena, LVS ou KLayout pendentes.

Não são aceitos falsos paths globais, desativação de LVS/DRC ou relaxamento de
clock para produzir aprovação artificial. Exceções temporais devem ser locais,
documentadas e justificadas pelo contrato funcional.

## Limites atuais

Mesmo um run limpo deste core não constitui tapeout final. Permanecem
obrigatórios o padframe real, caracterização Liberty multicorner das macros,
IR drop, potência com atividade representativa, CVC/ERC, simulação gate-level
com SDF e revisão do encapsulamento.
