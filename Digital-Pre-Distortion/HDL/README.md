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

# Matemática dos Blocos de DSP

Esta seção descreve a matemática usada pelos três blocos críticos do HDL:
`gmp_engine.v`, `mac_engine.v` e `metric_engine.v`. A descrição abaixo segue a
implementação atual, incluindo quantização, saturação e simplificações adotadas
para síntese em SKY130.

## Convenção Numérica

As amostras complexas são representadas por:

```text
x[n] = x_i[n] + j.x_q[n]
```

com `x_i` e `x_q` em signed Q1.15. Portanto, cada componente usa 16 bits e
representa aproximadamente o intervalo:

```text
-1.0000 <= x < +0.99997
```

Os coeficientes complexos do DPD são representados por:

```text
c_k = a_k + j.b_k
```

com `a_k` e `b_k` em signed Q2.16, armazenados como palavras de 18 bits. No
banco de coeficientes, cada termo GMP ocupa dois endereços:

```text
addr = 2*k     -> Re{c_k}
addr = 2*k + 1 -> Im{c_k}
```

As acumulações internas usam larguras maiores, principalmente 48 e 64 bits,
para reduzir overflow durante produtos e somas. A saída final do caminho rápido
é saturada para signed Q1.15.

## GMPengine

O `GMPengine` implementa a inferência DPD usando 39 termos GMP complexos. O
modelo geral pode ser escrito como:

```text
y[n] = sum_{k=0}^{38} c_k . phi_k[n]
```

em que `phi_k[n]` é um termo de base GMP e `c_k` é o coeficiente complexo
treinado. A base usada no HDL segue:

```text
phi_k[n] = x_mx(k)[n] . |x_ma(k)[n]|^p(k)
```

O bloco trabalha com uma janela de cinco amostras:

```text
x_0, x_1, x_2, x_3, x_4
```

em que `x_2` é a amostra central associada à saída validada. As posições `x_3`
e `x_4` existem para preservar o lookahead de duas amostras adotado no contrato
com o OpenDPD. Isso explica por que alguns testbenches adicionam duas amostras
nulas ao fim do vetor: elas esvaziam o pipeline sem perder as últimas saídas
úteis.

O conjunto de 39 termos é formado por:

```text
3 termos lineares:  p = 0, mx = 0,1,2
36 termos não lineares: p = 1,2,3,4 com 9 combinações por ordem
```

Para cada ordem não linear `p`, as nove combinações de posição são:

```text
(mx, ma) = (0,0), (1,1), (2,2),
           (0,1), (1,2), (2,3),
           (0,2), (1,3), (2,4)
```

Assim, o modelo inclui termos alinhados, atrasados e com dependência de
amplitude deslocada, que é o ponto central do GMP frente a um polinômio de
memória simples.

A magnitude usada nos termos é:

```text
|x_m| = sqrt(x_i,m^2 + x_q,m^2)
```

No HDL, essa raiz é calculada por uma função inteira `isqrt32`. As potências de
magnitude são calculadas em Q1.15:

```text
|x|^0 = 1.0
|x|^p = (|x| . |x|^(p-1)) >> 15
```

O termo de base preserva a fase da amostra complexa selecionada e escala sua
amplitude:

```text
phi_i = (x_i,mx . |x_ma|^p) >> 15
phi_q = (x_q,mx . |x_ma|^p) >> 15
```

para `p > 0`. Para `p = 0`, o termo é simplesmente:

```text
phi_i = x_i,mx
phi_q = x_q,mx
```

A multiplicação pelo coeficiente complexo é:

```text
c_k . phi_k =
(a_k + j.b_k)(phi_i + j.phi_q)
```

logo:

```text
y_i += ((phi_i . a_k) - (phi_q . b_k)) >> 16
y_q += ((phi_i . b_k) + (phi_q . a_k)) >> 16
```

O deslocamento de 16 bits após a multiplicação corresponde à escala Q2.16 dos
coeficientes. Depois da soma dos 39 termos, o resultado acumulado é saturado:

```text
y_i_sat = sat16(y_i)
y_q_sat = sat16(y_q)
```

Na versão funcional do HDL, o pipeline é organizado em estágios: formação da
janela, cálculo de magnitudes, acumulação por grupos de termos e registro da
saída. Na versão OpenLane serializada, a mesma matemática é preservada, mas a
acumulação é distribuída em quatro fases para reduzir área.

## MACcore e NLMS

O `MACcore` executa o treinamento interno em background a partir de um snapshot
capturado da RAM. Cada posição da RAM contém:

```text
ref[n] = ref_i[n] + j.ref_q[n]
fb[n]  = fb_i[n]  + j.fb_q[n]
```

O treinamento usa o feedback como base de regressão e a referência como alvo.
Essa escolha segue a lógica de aprendizagem indireta: a cadeia de observação
fornece o sinal já afetado pelo PA, e o treinamento busca coeficientes que
aproximem a referência a partir dessa base.

Para cada amostra válida da janela, o `MACcore` monta a mesma base GMP do
`GMPengine`:

```text
phi_k[n] = fb_mx(k)[n] . |fb_ma(k)[n]|^p(k)
```

Na primeira época, os coeficientes começam zerados. A partir da segunda passagem
e das seguintes, o bloco calcula a saída estimada pelo modelo corrente:

```text
y_hat[n] = sum_{k=0}^{38} w_k . phi_k[n]
```

e o erro de modelo:

```text
e[n] = ref[n] - y_hat[n]
```

O acumulador de qualidade da época é baseado em norma L1:

```text
E_epoch = sum_n (|Re{e[n]}| + |Im{e[n]}|)
```

Para cada termo `k`, o bloco acumula numerador e denominador da atualização
NLMS:

```text
N_k = sum_n e[n] . conj(phi_k[n])
D_k = sum_n |phi_k[n]|^2
```

Expandindo para partes real e imaginária:

```text
N_real,k = sum_n (e_i[n].phi_i,k[n] + e_q[n].phi_q,k[n])
N_imag,k = sum_n (e_q[n].phi_i,k[n] - e_i[n].phi_q,k[n])
D_k      = sum_n (phi_i,k[n]^2 + phi_q,k[n]^2)
```

A atualização aplicada é:

```text
Delta w_k = mu . N_k / (epsilon + D_k)
w_k       = sat_Q2.16(w_k + Delta w_k)
```

No HDL atual:

```text
epsilon = 1
mu      = 1 / 4
```

O fator `mu = 1/4` é implementado por deslocamento:

```text
NLMS_MU_SHIFT = 2
```

A divisão é serial, por subtração/restauração, para evitar um divisor
combinacional grande. O quociente é escalado antes da saturação para Q2.16.
Depois da atualização de todos os 39 termos, a época termina.

O controle de época implementado é:

```text
max_epochs = 20
min_epochs = 10
```

O melhor conjunto de coeficientes é aquele com menor `E_epoch`. O treinamento
para quando atinge 20 épocas ou quando, após pelo menos 10 épocas, o erro da
época atual fica pior que o melhor erro já observado. Ao final, o `MACcore`
escreve no banco inativo os 78 valores:

```text
Re{w_0}, Im{w_0}, Re{w_1}, Im{w_1}, ..., Re{w_38}, Im{w_38}
```

e sinaliza `coef_ready` para que o controlador possa solicitar a troca de banco
em um `sync_event`.

Essa implementação não é um LS/RLS completo com solução matricial acoplada.
Ela é uma atualização block-NLMS por termo, escolhida por ser menor,
sintetizável e compatível com treinamento lento em background.

## MetricEngine

O `MetricEngine` calcula métricas leves em hardware. Ele não tenta calcular
EVM, NMSE ou ACLR em tempo real, porque essas métricas exigiriam divisões,
normalização estatística, FFT ou processamento espectral. Em vez disso, o bloco
usa aproximações L1 e acumuladores EWMA que servem como indicadores de
degradação.

A magnitude L1 da saída DPD é:

```text
mag_dpd[n] = |dpd_i[n]| + |dpd_q[n]|
```

A magnitude L1 da referência é:

```text
mag_ref[n] = |ref_i[n]| + |ref_q[n]|
```

O erro REF-FB é:

```text
err_l1[n] = |ref_i[n] - fb_i[n]| + |ref_q[n] - fb_q[n]|
```

O drift entre esforço de pre-distorção e referência é:

```text
drift_l1[n] = |mag_dpd[n] - mag_ref[n]|
```

As métricas são atualizadas com fator EWMA de `1/256`:

```text
metric_power <- metric_power - (metric_power >> 8) + mag_dpd
metric_error <- metric_error - (metric_error >> 8) + err_l1
metric_drift <- metric_drift - (metric_drift >> 8) + drift_l1
```

Esses registradores não estão em dB. Como a forma implementada soma a nova
amostra sem dividir por 256, o valor em regime permanente se aproxima de 256
vezes a média L1 do sinal observado. Isso foi feito de propósito para evitar
divisões no caminho de métricas.

O clipping é contado quando a saída DPD ou o feedback excede o limite:

```text
clip[n] = (|dpd_i| > CLIP_LEVEL) or (|dpd_q| > CLIP_LEVEL) or
          (|fb_i|  > CLIP_LEVEL) or (|fb_q|  > CLIP_LEVEL)
```

com:

```text
CLIP_LEVEL = 30000
```

Quando `clip[n]` é verdadeiro, `metric_clipping` é incrementado com saturação em
32 bits. O pedido de retreinamento é puramente comparativo:

```text
retrain_request =
    metrics_valid and
    (metric_error    > threshold_error or
     metric_drift    > threshold_drift or
     metric_clipping > threshold_clip)
```

Os limiares são programáveis por registradores. Em operação, o PicoRV32 lê essas
métricas, decide a política de captura/treinamento e coordena a atualização dos
bancos de coeficientes.

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
