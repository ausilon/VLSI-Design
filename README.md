# VLSI Implementation of DPD for Next-Generation Digital TV Transmitters

Este repositório documenta uma prova de conceito acadêmica de uma implementação
em HDL de um sistema de pre-distorção digital (DPD) para transmissores de TV
digital de próxima geração, com foco em sinais OFDM de 6 MHz, validação
algorítmica com GNU Radio/OpenDPD e avaliação física em SKY130/OpenLane.

O projeto combina três frentes:

- geração e preparação de datasets IQ para validação;
- implementação HDL do caminho de inferência, métricas e treinamento;
- síntese, floorplan e montagem física preliminar em SKY130.

## Natureza do Trabalho

Este trabalho deve ser lido como uma prova de conceito técnico-científica. O
objetivo principal é demonstrar a viabilidade de uma arquitetura DPD integrada,
com inferência, métricas, captura e treinamento interno, partindo de um fluxo de
software até uma avaliação física preliminar.

A maior parte do fluxo foi construída com ferramentas abertas ou acessíveis em
ambiente acadêmico/estudantil:

- GNU Radio para geração e manipulação de sinais baseband;
- Python/NumPy para conversão, análise e preparação dos datasets;
- OpenDPD como referência algorítmica de treinamento;
- Verilog/SystemVerilog para implementação e verificação HDL;
- Questa Intel FPGA Edition para simulação HDL;
- OpenLane/OpenROAD/Yosys/Magic/KLayout com PDK SKY130 para avaliação física.

Assim, os resultados apresentados não devem ser interpretados como um produto
industrial final ou um tapeout completo. Eles representam uma trilha
reprodutível de validação de conceito, adequada para discutir arquitetura,
quantização, throughput, custo em área, gargalos físicos e próximos passos.

## Estado Atual

O desenvolvimento local avançou além da versão inicial deste repositório. A
branch de documentação consolida o estado atual:

- `GMPengine`: motor de inferência GMP com 39 termos e coeficientes complexos
  Q2.16;
- `MetricEngine`: métricas de potência, erro REF-FB, drift DPD-REF e clipping;
- `MACcore`: treinamento interno baseado em NLMS, preservando a base GMP;
- `dpd_top`: fluxo integrado com bypass, captura, treino, troca de banco de
  coeficientes e pedido de retreinamento;
- datasets sintético, ATSC 3.0/A/322 e coeficientes exportados do OpenDPD;
- wrappers e configurações OpenLane/SKY130 para macros físicas;
- montagem física preliminar do SoC em nível de macros.

## Organização

```text
Digital-Pre-Distortion/
├── HDL/
│   ├── rtl/          HDL final desta prova de conceito
│   ├── tb/           testbenches SystemVerilog
│   └── sim/          scripts .do e vetores pequenos de simulação
├── datasets/         datasets de reprodução selecionados
├── openlane/         projetos OpenLane sem runs compilados
├── scripts/          conversão/exportação de dados
└── docs/             artigo, figuras, referências e log técnico
```

## Política de Versionamento

São versionados arquivos de projeto: HDL, testbenches, scripts, configurações,
documentação, figuras essenciais e datasets necessários para reprodução.

Não são versionados diretórios `runs/` do OpenLane, bibliotecas `work/` do
Questa, arquivos `.wlf`, GDS/LEF/SPICE/SDF gerados, logs longos, caches e
binários compilados.

## Resultado Físico Preliminar

A implementação física ainda não é um chip pronto para foundry. O estado atual é
um scaffold macro-level útil para avaliação de área, floorplan e documentação.
Essa distinção é importante: o projeto já produz evidências físicas em SKY130,
mas ainda precisa de padframe, conectividade completa, fechamento de timing,
LVS/STA final e revisão de integração antes de ser tratado como tapeout.

Resultado consolidado até aqui:

- macros menores com DRC/LVS limpos;
- `GMPengine` e `MACcore` sintetizados como blocos críticos;
- top físico preliminar com Magic DRC limpo;
- LVS do top ainda aberto porque o padframe e a conectividade funcional completa
  ainda não foram fechados.

O `GMPengine` atual opera com iniciação de 4 ciclos por amostra. Com o resultado
físico preliminar de aproximadamente 90,9 MHz, o throughput ativo fica em torno
de 22,7 Msps. A meta de 24 Msps exige pelo menos 96 MHz ou uma revisão
microarquitetural para reduzir o intervalo de iniciação.

## Documentação Principal

- [Arquitetura HDL](Digital-Pre-Distortion/HDL/README.md)
- [Datasets](Digital-Pre-Distortion/datasets/README.md)
- [Fluxo OpenLane/SKY130](Digital-Pre-Distortion/openlane/README.md)
- [Estado técnico](Digital-Pre-Distortion/docs/status.md)
- [Log técnico v3](Digital-Pre-Distortion/docs/project_log_v3.md)

## Nota Sobre Evolução

Durante o desenvolvimento existiram versões intermediárias, como `rtl_v2`,
`simv2` e snapshots específicos de OpenLane. Nesta branch, a estrutura pública
mantém apenas a versão final selecionada para revisão. A evolução do projeto é
descrita nos textos técnicos, evitando duplicar código antigo e reduzir a
clareza da validação.
