# HDL Architecture

Este diretório mantém a implementação HDL do DPD SoC.

## Diretórios

```text
rtl/      HDL final desta prova de conceito
tb/       testbenches SystemVerilog
sim/      scripts Questa e vetores pequenos
```

## Arquitetura Atual

O HDL final separa o sistema em caminho rápido, caminho lento de treinamento e
plano de controle.

| Módulo | Papel |
|---|---|
| `dpd_top.v` | integração do DPD |
| `gmp_engine.v` | inferência GMP em tempo real |
| `mac_engine.v` | treinamento interno NLMS |
| `metric_engine.v` | métricas para retreinamento |
| `capture_ram_pingpong.v` | captura REF/FB |
| `coef_bank_a.v`, `coef_bank_b.v` | armazenamento de coeficientes |
| `coef_switch_ctrl.v` | troca sincronizada de banco |
| `axi_lite_regs.v` | registradores de controle/status |
| `soc_top.v` | integração com PicoRV32 e periféricos |

## Validação em Questa

Scripts principais:

```text
sim/run_dpd_top_full_system.do
sim/run_dpd_top_gmp_metric_integration.do
sim/run_dpd_top_internal_train_full_gmp.do
sim/run_mac_engine_nlms.do
```

Teste integrado esperado:

```text
boot em bypass -> capture -> train -> banco B -> DPD ativo
-> métricas disparam retreino -> nova captura -> train banco A
-> switch sincronizado
```

## Observação Sobre Throughput

Na versão OpenLane serializada do `GMPengine`, o bloco usa 4 ciclos por amostra
em modo DPD ativo. Portanto:

```text
throughput = Fclk / 4
```

Para 24 Msps, o clock mínimo é 96 MHz. O resultado físico preliminar de 90,9 MHz
indica que ainda falta margem de timing ou redução do intervalo de iniciação.
