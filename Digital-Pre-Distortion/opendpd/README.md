# Estudos com OpenDPD

Este diretório documenta a etapa algorítmica conduzida no OpenDPD. Os arquivos
pesados de treinamento, checkpoints, logs completos e modelos `.pt` não são
versionados. O objetivo aqui é registrar o método, os parâmetros principais e os
contratos que foram levados para a implementação HDL.

O ambiente de treinamento foi baseado no projeto OpenDPD:

```text
https://github.com/lab-emi/OpenDPD.git
```

O sinal ATSC 3.0 usado como entrada veio do projeto `gr-atsc3`, usando o exemplo
`vv031.grc` como referência de cadeia transmissora:

```text
https://github.com/drmpeg/gr-atsc3
```

O OpenDPD foi usado como ambiente de referência porque já oferece uma estrutura
prática para comparar sinal de entrada, modelo de PA, saída distorcida e sinal
corrigido por DPD. Essa etapa permitiu validar o comportamento esperado antes
de comprometer área em hardware. Em vez de partir diretamente para uma descrição
HDL, o fluxo primeiro mediu se o modelo adotado era capaz de corrigir um sinal
OFDM representativo do transmissor de TV digital.

![OpenDPD overview](figures/overview_test.gif)

---

# Fluxo de Treinamento

O estudo foi organizado em duas fases. Na primeira, o OpenDPD treinou ou
carregou um modelo de PA. Esse modelo representa a não linearidade de amplitude,
a rotação de fase e os efeitos de memória que aparecem quando um amplificador
opera próximo de sua região eficiente. Na segunda fase, foi treinado o DPD, que
aprende uma função inversa aproximada: sua saída é propositalmente
pre-distorcida para que, após passar pelo PA, o sinal resultante volte a se
aproximar da referência linear.

Essa separação foi importante para a arquitetura digital. O PA não é parte do
ASIC digital; ele pertence à cadeia analógica/RF do transmissor. O chip digital
precisa receber uma referência I/Q, aplicar a pre-distorção e observar um
feedback vindo da cadeia de amostragem do PA. Portanto, o modelo de PA treinado
no OpenDPD serviu como ambiente controlado para avaliar o algoritmo, enquanto o
modelo DPD treinado serviu como referência para definir os coeficientes e a
estrutura do `GMPengine`.

---

# Algoritmo Selecionado

O modelo escolhido para a sequência HDL foi o GMP, Generalized Memory
Polynomial. Ele foi adotado por combinar boa aderência ao problema de DPD com
uma estrutura de implementação compatível com hardware digital: atrasos de
amostras, geração de termos não lineares, multiplicação por coeficientes
complexos e acumulação.

Modelos neurais ou estruturas mais genéricas poderiam atingir desempenho maior
em alguns cenários, mas tenderiam a aumentar a dificuldade de síntese, a área e
a validação em SKY130. O GMP oferece uma fronteira mais controlável entre
desempenho algorítmico e custo físico, principalmente para um projeto que mira
24 MS/s e precisa manter o bloco de inferência em tempo real.

A configuração consolidada para o predistorter foi:

```text
DPD_S_0_M_GMP_H_15_F_64_P_39
```

Para a implementação HDL, o parâmetro mais relevante é `P_39`, que define 39
termos GMP. Como os coeficientes são complexos, cada termo exige componente real
e imaginária. Esse ponto levou à decisão de implementar bancos de coeficientes
complexos em Q2.16 e abandonar a versão simplificada com coeficientes reais
escalares.

---

# Resultados Usados como Referência

O estudo final usado como referência do HDL foi conduzido com o dataset
ATSC 3.0/A/322 baseado no exemplo `vv031.grc`, canal de 6 MHz, FFT 8K,
modulação 256-QAM e taxa de saída de 24 MS/s. O melhor ponto registrado para o
treinamento DPD ocorreu na época 12 de 15.

| Métrica | Validação | Teste |
|---|---:|---:|
| NMSE | -55,15 dB | -57,47 dB |
| EVM | -59,13 dB | -61,00 dB |
| ACLR médio | -53,56 dB | -46,45 dB |

Os valores de NMSE e EVM indicaram que o modelo foi capaz de aproximar bem a
saída linear desejada. A diferença entre validação e teste no ACLR foi mantida
como observação técnica, porque o ACLR depende fortemente do trecho temporal
avaliado, da energia instantânea próxima às bordas de banda e das janelas de
medição. Mesmo com essa diferença, o resultado foi considerado suficiente para
definir a estrutura de inferência e iniciar a implementação HDL fiel ao modelo
GMP treinado.

---

# Contratos Derivados para HDL

A etapa OpenDPD definiu os contratos que passaram a orientar os blocos digitais.
As amostras foram fixadas em signed Q1.15, com 16 bits para I e 16 bits para Q.
Os coeficientes foram fixados em signed Q2.16, com 18 bits para cada componente
real e imaginária. O `GMPengine` passou a implementar 39 termos complexos, e os
testbenches passaram a carregar coeficientes exportados do OpenDPD para comparar
a saída HDL com vetores de referência.

Também ficou definido que o treinamento interno não precisa reproduzir todo o
ambiente OpenDPD dentro do chip. O papel do `MACcore` é atualizar coeficientes a
partir de snapshots REF/FB usando uma forma incremental viável em hardware. O
OpenDPD permanece como referência offline para dataset, métricas e comparação
numérica, enquanto o HDL implementa o subconjunto necessário para operação
embarcada.

As métricas seguiram a mesma lógica. NMSE, EVM e ACLR são preservadas como
métricas de análise offline. No hardware, o `MetricEngine` calcula observáveis
mais baratos: potência L1, erro REF-FB, drift DPD-REF e eventos de clipping.
Esses sinais são suficientes para indicar degradação e solicitar novo
treinamento ao controlador, sem colocar um analisador espectral completo dentro
do ASIC.
