# Digital Pre-Distortion Subproject

Este diretório contém o fluxo técnico do DPD: dataset, modelo algorítmico,
implementação HDL, verificação e preparação física em SKY130.

## Escopo Como Prova de Conceito

O trabalho busca consolidar uma cadeia completa de estudo, e não entregar ainda
um circuito integrado final. A contribuição principal é conectar, em um mesmo
fluxo experimental, a geração de sinal, o treinamento DPD, a quantização dos
coeficientes, a validação HDL e a estimativa física em SKY130.

Por esse motivo, algumas decisões privilegiam rastreabilidade e reprodução:

- datasets pequenos o suficiente para simulação de terceiros;
- testbenches determinísticos em vez de dependência exclusiva de bancada RF;
- coeficientes exportados do OpenDPD como referência;
- separação entre HDL funcional final e variantes OpenLane de avaliação física;
- documentação explícita dos pontos ainda não fechados para foundry.

As ferramentas usadas são majoritariamente abertas ou disponíveis em contexto
acadêmico/estudantil. Isso torna o fluxo mais acessível, mas também exige
cuidado ao interpretar resultados físicos preliminares, principalmente timing,
LVS de top-level e qualidade final de tapeout.

## Fluxo de Sistema

O sistema inicia em bypass porque ainda não existe modelo treinado do
amplificador de potência (PA). Durante esse período, as amostras de referência e
feedback são capturadas e sincronizadas. O `MACcore` usa essa captura para
atualizar os coeficientes do modelo DPD. Após o treinamento, o banco inativo de
coeficientes é escrito e a troca de banco ocorre em evento síncrono.

Fluxo operacional:

```text
bypass inicial
-> captura REF/FB
-> treinamento NLMS no MACcore
-> escrita no banco de coeficientes inativo
-> troca sincronizada de banco
-> DPD ativo via GMPengine
-> MetricEngine monitora erro/drift/clipping
-> pedido de retreinamento quando necessário
```

## Blocos Principais

| Bloco | Função |
|---|---|
| `PicoRV32` | política de controle, registradores, status e disparos |
| `AXI-Lite` | plano de controle e visibilidade de status |
| `Capture RAM` | snapshot de REF/FB para treinamento |
| `Coef Bank A/B` | bancos alternados de coeficientes complexos Q2.16 |
| `GMPengine` | inferência em tempo real do predistorter |
| `MACcore` | treinamento interno lento/background |
| `MetricEngine` | métricas para monitoramento e retreinamento |

## Quantização

| Sinal | Formato |
|---|---|
| Amostras I/Q | signed Q1.15, 16 bits |
| Coeficientes | signed Q2.16, 18 bits |
| Modelo GMP | 39 termos complexos |
| Baseband alvo | 24 Msps para canal de 6 MHz |

## Estado de Validação

O contrato algorítmico foi validado com datasets gerados por GNU Radio e
treinamento OpenDPD. O HDL v2 foi validado em Questa com testbenches unitários e
integração do `dpd_top`.

O próximo passo crítico é fechar margem física do `GMPengine` acima de 96 MHz ou
reduzir o intervalo de iniciação para manter 24 Msps com folga.
