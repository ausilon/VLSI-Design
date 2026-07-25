# VLSI Implementation of DPD for Next-Generation Digital TV Transmitters

Este repositório reúne o desenvolvimento de um sistema de pre-distorção digital
(Digital Predistortion, DPD) para transmissores de televisão digital de próxima
geração. O trabalho parte da geração de sinais OFDM em banda-base, passa pela
modelagem e treinamento do DPD, avança para a implementação em HDL e termina em
uma avaliação física preliminar com OpenLane e SKY130.

A motivação principal é estudar uma arquitetura digital capaz de compensar as
não linearidades de um amplificador de potência em um transmissor de TV digital.
O alvo de validação adotado é um sinal de canal de 6 MHz, representado como
banda-base complexa I/Q em 24 MS/s. Essa escolha permite trabalhar com uma taxa
compatível com o processamento digital do sinal e, ao mesmo tempo, manter margem
para observar distorções espectrais relevantes para DPD.

O projeto utiliza predominantemente ferramentas abertas e ferramentas acessíveis
em ambiente acadêmico. A geração de sinais foi feita com GNU Radio, a etapa de
treinamento utilizou OpenDPD, a verificação HDL foi conduzida no Questa Intel
FPGA Edition e a avaliação física foi preparada com OpenLane, OpenROAD, Yosys,
Magic, KLayout e o PDK aberto SKY130. Essa combinação foi adotada para permitir
reprodutibilidade, reduzir barreiras de acesso e manter o fluxo técnico
auditável por outros pesquisadores.

---

# Visão Geral do Fluxo

O fluxo foi organizado de forma incremental. Primeiro foi gerado um dataset em
banda-base complexa, usando uma cadeia ATSC 3.0 no GNU Radio como fonte de
excitação. Esse dataset foi convertido para os formatos usados tanto pelo
OpenDPD quanto pelos testbenches HDL. Em seguida, o OpenDPD foi usado para
treinar um modelo GMP e produzir coeficientes de referência. Esses coeficientes
foram quantizados em Q2.16 e aplicados ao motor HDL de inferência.

Na parte digital, o sistema foi dividido em três funções principais. O
`GMPengine` executa a inferência em tempo real e aplica a pre-distorção ao fluxo
I/Q. O `MetricEngine` observa potência, erro entre referência e feedback,
clipping e drift entre o sinal pre-distorcido e a referência. O `MACcore` executa
o treinamento interno em segundo plano, usando amostras capturadas da RAM e
atualizando o banco de coeficientes inativo.

Depois da validação funcional em simulação, os blocos foram preparados para
avaliação física em SKY130. A estratégia adotada foi modular: sintetizar e
avaliar primeiro os blocos menores, depois os blocos críticos de maior área
(`GMPengine` e `MACcore`) e, por fim, montar um top-level físico com macros.

---

# Organização do Repositório

A árvore pública mantém somente as versões finais selecionadas para revisão.
Versões intermediárias, diretórios de simulação compilados e runs completos de
OpenLane não são versionados. A evolução do trabalho é descrita nos documentos,
sem duplicar código antigo.

```text
Digital-Pre-Distortion/
├── HDL/
│   ├── rtl/          implementação HDL atual
│   ├── tb/           testbenches SystemVerilog
│   └── sim/          scripts Questa e vetores pequenos
├── gnu-radio/        flowgraph final usado para gerar o dataset ATSC 3.0
├── datasets/         datasets selecionados para reprodução
├── scripts/          conversão, quantização e exportação de coeficientes
├── openlane/         projetos OpenLane sem artefatos compilados
└── docs/             artigo, figuras, referências e estado técnico
```

---

# Geração do Dataset com GNU Radio

O dataset principal foi gerado a partir de uma cadeia ATSC 3.0 baseada no
projeto `gr-atsc3`, disponível em:

```text
https://github.com/drmpeg/gr-atsc3
```

O flowgraph usado como ponto de partida foi o exemplo `vv031.grc`. Ele foi
adaptado localmente para gerar um sinal em banda-base complexa adequado ao
treinamento DPD e à validação HDL. A entrada usada foi um arquivo de transporte
MPEG-TS (`sample_1280x720.ts`), e a saída foi convertida para amostras complexas
em 24 MS/s.

![GNU Radio ATSC 3.0 flowgraph](Digital-Pre-Distortion/docs/figures/gnuradio_atsc3_a322_vv031_flowgraph.png)

O dataset resultante preserva os parâmetros principais do cenário estudado:
canal de 6 MHz, FFT 8K, modulação 256-QAM, amostragem de saída em 24 MS/s e
representação complexa I/Q. Para a simulação HDL, o mesmo sinal foi convertido
para Q1.15 e armazenado em arquivos `.hex`, mantendo nomes padronizados
(`ref_iq_q15.hex`, `feedback_iq_q15.hex` e capturas esperadas) para facilitar a
troca de datasets nos testbenches.

---

# Arquitetura Digital

O sistema inicia em bypass, pois no primeiro momento ainda não há coeficientes
válidos para compensar o PA. Enquanto o caminho rápido encaminha a referência, a
RAM de captura registra pares de referência e feedback. O `MACcore` utiliza esse
snapshot para treinar coeficientes. Quando o treinamento termina, o banco
inativo é atualizado e a troca de banco ocorre em evento síncrono, evitando
glitches no caminho de amostras.

Após a ativação do DPD, o `GMPengine` passa a operar no caminho rápido. O
`MetricEngine` continua acompanhando a qualidade do sinal e pode solicitar novo
treinamento quando as métricas ultrapassam os limiares configurados. O PicoRV32
permanece como elemento de controle e política, sem executar processamento
pesado de DSP.

```text
bypass inicial
-> captura REF/FB
-> treinamento no MACcore
-> escrita no banco de coeficientes inativo
-> troca sincronizada de banco
-> inferência em tempo real no GMPengine
-> métricas e possível retreinamento
```

---

# Síntese Física e OpenLane

O fluxo físico foi estruturado por macros, seguindo a mesma estratégia modular
do HDL. Os blocos de controle e periféricos foram sintetizados separadamente,
enquanto RAM de captura e bancos de coeficientes foram tratados como macros com
SRAM. Essa separação evita que memórias grandes sejam implementadas
integralmente em flip-flops e permite estudar a ocupação física de cada bloco.

O `GMPengine` é o bloco de maior pressão de timing porque pertence ao caminho
rápido. Na versão atual para OpenLane ele foi serializado em quatro fases,
mantendo 39 termos GMP complexos, amostras Q1.15 e coeficientes Q2.16. Com essa
arquitetura, o throughput em modo DPD ativo é `Fclk/4`. O resultado físico
preliminar ficou próximo de 90,9 MHz, o que equivale a aproximadamente
22,7 MS/s. Para atingir 24 MS/s com margem, o próximo fechamento físico precisa
superar 96 MHz ou reduzir o intervalo de iniciação.

O top-level físico atual é uma montagem de macros usada para avaliar área,
floorplan e integração preliminar. Ele ainda não deve ser tratado como tapeout
final, pois falta fechar padframe, conectividade funcional completa, LVS/STA de
chip completo e a estratégia definitiva de IO/alimentação.

---

# Documentação Principal

- [Fluxo DPD](Digital-Pre-Distortion/README.md)
- [Arquitetura HDL](Digital-Pre-Distortion/HDL/README.md)
- [GNU Radio](Digital-Pre-Distortion/gnu-radio/README.md)
- [Datasets](Digital-Pre-Distortion/datasets/README.md)
- [OpenLane/SKY130](Digital-Pre-Distortion/openlane/README.md)
- [Estado técnico](Digital-Pre-Distortion/docs/status.md)
- [Log técnico v3](Digital-Pre-Distortion/docs/project_log_v3.md)

---

# Política de Versionamento

O repositório mantém arquivos necessários para análise e reprodução do fluxo:
HDL, testbenches, scripts, flowgraphs, metadados, datasets selecionados,
configurações OpenLane e documentação. Não são versionados diretórios `runs/`,
bibliotecas `work/`, arquivos `.wlf`, GDS/LEF/DEF/SPICE/SDF/LIB gerados, logs
longos, caches e binários compilados.
