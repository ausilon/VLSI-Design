# Digital Pre-Distortion para Transmissores de TV Digital

Este diretório concentra o desenvolvimento do subsistema DPD. A organização foi
pensada para deixar claro como o trabalho evolui da geração do sinal até a
implementação física: primeiro é criado um sinal de excitação em banda-base,
depois o comportamento do PA e do DPD é estudado em software, em seguida o
algoritmo é convertido para uma arquitetura HDL e, por fim, os blocos são
avaliados em um fluxo físico compatível com SKY130.

O objetivo técnico é implementar um predistorter digital capaz de operar sobre
amostras I/Q de um transmissor OFDM. O cenário de estudo usa canal de 6 MHz e
amostragem de 24 MS/s. O algoritmo de referência é um modelo GMP com 39 termos,
coeficientes complexos em Q2.16 e amostras signed Q1.15.

---

# Funcionamento do Sistema

O sistema foi definido para operar em dois caminhos de dados. O caminho rápido
processa as amostras que seguem para o transmissor. O caminho lento realiza
captura, análise e treinamento. Essa divisão foi adotada porque o treinamento é
computacionalmente mais pesado, mas não precisa ocorrer em tempo real amostra a
amostra. Em uma implementação ASIC de baixo custo, separar inferência e
treinamento reduz a pressão por área e por quantidade de multiplicadores.

Durante a inicialização, o DPD permanece em bypass. Nessa fase, o sistema ainda
não possui coeficientes válidos para compensar o PA. As amostras de referência e
feedback são então capturadas em uma RAM ping-pong. O `MACcore` lê essa captura
e executa o treinamento NLMS sobre a mesma base GMP usada na inferência. Ao
final do treinamento, os coeficientes são gravados no banco inativo. A troca de
banco é feita apenas em `sync_event`, de forma sincronizada com o fluxo de
amostras.

Quando o DPD está ativo, o `GMPengine` aplica os coeficientes ao sinal de
referência e gera a versão pre-distorcida. O `MetricEngine` monitora a potência,
o erro REF-FB, o drift entre DPD e referência e eventos de clipping. Essas
métricas são expostas ao plano de controle e podem disparar novo treinamento.
O PicoRV32 atua como controlador de política, habilitando capturas, verificando
status e coordenando a sequência geral, sem executar as operações pesadas de
DSP.

---

# Blocos do HDL

| Bloco | Função no sistema |
|---|---|
| `PicoRV32` | controle, política de operação, leitura de status e disparos |
| `AXI-Lite` | plano de registradores para controle e observabilidade |
| `Capture RAM` | armazenamento temporário de pares REF/FB para treinamento |
| `Coef Bank A/B` | bancos alternados de coeficientes complexos Q2.16 |
| `GMPengine` | inferência do predistorter no caminho rápido |
| `MACcore` | treinamento NLMS em background |
| `MetricEngine` | cálculo de métricas para supervisão e retreinamento |

---

# Dataset e OpenDPD

O sinal de validação principal foi gerado no GNU Radio a partir do módulo
externo `gr-atsc3`, usando o exemplo `vv031.grc` como base. Esse exemplo fornece
uma cadeia transmissora ATSC 3.0 com blocos como scrambler, BCH/LDPC,
interleaver, mapper, geração de pilotos, bootstrap e prefixo cíclico. A cadeia
foi adaptada para usar um arquivo `.ts` de entrada e salvar a saída como
banda-base complexa.

O arquivo de saída em float complexo foi convertido para três usos:

1. dataset OpenDPD, usado para modelar o PA e treinar o DPD;
2. dataset Q1.15 em `.hex`, usado pelos testbenches HDL;
3. arquivos auxiliares de captura esperada, usados para validar RAM e alinhamento.

A etapa OpenDPD treinou um PA e um predistorter GMP. Os coeficientes finais do
predistorter foram exportados para Q2.16 e carregados nos testbenches do
`GMPengine`. Dessa forma, o HDL não foi validado apenas com números artificiais:
ele também foi comparado contra vetores derivados do modelo treinado em
software.

Os estudos algorítmicos completos estão documentados em
[opendpd/README.md](opendpd/README.md). Essa documentação registra o uso do
OpenDPD como referência para escolha do modelo GMP, interpretação das métricas
NMSE/EVM/ACLR, exportação dos coeficientes e definição dos contratos de
quantização adotados no HDL.

---

# Validação HDL

Os testbenches foram escritos em SystemVerilog e executados no Questa. A
validação foi feita de forma incremental: primeiro blocos pequenos, depois
`GMPengine`, `MetricEngine`, `MACcore` e, por último, o fluxo completo em
`dpd_top`.

O teste integrado exercita a sequência:

```text
boot em bypass -> captura -> treino -> escrita de coeficientes
-> troca de banco -> DPD ativo -> métricas -> retreinamento
```

Essa validação garante coerência funcional entre o contrato de dataset, o plano
de controle, a RAM de captura, os bancos de coeficientes e os blocos críticos de
DSP. Ela foi concluída na linha funcional `rtl_v2`: o
`tb_dpd_top_gmp_metric_integration` comparou 64 saídas do top contra o golden
OpenDPD e leu as métricas integradas; em seguida, o
`tb_dpd_top_full_system` validou captura, treinamento NLMS, escrita e troca dos
bancos A/B, DPD ativo, métricas, IRQ e retreinamento. Ambos foram registrados
com `TB PASS` no `simv2`.

---

# Avaliação Física

Para SKY130/OpenLane, o projeto foi reorganizado em blocos físicos. Os blocos
menores (`MetricEngine`, PicoRV32, AXI-Lite e periféricos) foram avaliados como
macros standard-cell. A RAM de captura e os bancos de coeficientes foram
preparados com SRAM hard macro. Os dois blocos críticos, `GMPengine` e
`MACcore`, receberam versões específicas de OpenLane para reduzir área e pressão
de roteamento.

O `GMPengine` preserva o modelo GMP de 39 termos e coeficientes complexos e foi
serializado em quatro fases para reduzir área. A implementação física atual usa
dez lanes pipelineadas com latência fixa. Em 100 MHz, o intervalo de iniciação
de quatro ciclos fornece 25 MS/s e atende o contrato de 24 MS/s.

O `MACcore`, por outro lado, é um bloco de treinamento em background. Mesmo
serializado, ele mantém folga temporal grande em relação ao alvo de treinamento
em minutos, porque opera sobre snapshots de RAM e não sobre cada amostra em
tempo real.

---

# Estado Atual

O sistema HDL demonstrou em simulação o fluxo funcional principal. As revisões
serializadas usadas no OpenLane possuem validação golden independente: o
GMPengine reproduziu 64 saídas I/Q bit-exatas do OpenDPD, e o MACcore reproduziu
checkpoints e coeficientes do golden NLMS de software. Portanto, a regressão
conjunta de RAM, bancos, motores DSP e métricas está fechada para o `rtl_v2`.
A pendência é portar e repetir essa regressão com as revisões serializadas
exatas do OpenLane, cujas latências e interfaces físicas diferem da linha
funcional.

A implementação OpenLane demonstra viabilidade física de síntese, floorplan,
placement e roteamento, com resultados positivos isolados de timing, DRC e LVS.
Esses resultados permanecem experimentais porque não existe ainda um conjunto
uniforme de runs completos para todas as macros e o top. Padframe, STA RCX
multicorner final, potência, IR drop e signoff de chip continuam pendentes.
