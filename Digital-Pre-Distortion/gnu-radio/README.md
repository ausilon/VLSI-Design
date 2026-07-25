# Geração do Dataset no GNU Radio

A geração do dataset foi uma etapa central do projeto, pois o DPD só é útil se
for treinado e validado com um sinal representativo do transmissor alvo. O sinal
adotado nesta fase é uma forma de onda ATSC 3.0/A/322 em banda-base complexa,
com canal de 6 MHz e saída em 24 MS/s.

O ponto de partida foi o projeto aberto `gr-atsc3`, disponível em:

```text
https://github.com/drmpeg/gr-atsc3
```

Dentro desse projeto foi usado o exemplo `examples/vv031.grc`. Esse flowgraph
contém uma cadeia transmissora ATSC 3.0 com processamento de entrada,
codificação, interleaving, mapeamento, pilotos, bootstrap e formação OFDM. A
versão mantida neste repositório foi adaptada para usar um arquivo de transporte
`.ts` como entrada e salvar a saída em banda-base complexa.

![Flowgraph GNU Radio](../docs/figures/gnuradio_atsc3_a322_vv031_flowgraph.png)

O arquivo principal é:

```text
atsc3_a322_vv031_8k_256qam_fs24m_baseband.grc
```

Também é mantida a versão Python gerada pelo GNU Radio Companion:

```text
atsc3_a322_vv031_8k_256qam_fs24m_baseband.py
```

---

# Parâmetros do Sinal

O dataset final registrado em `datasets/atsc3_a322_vv031_8k_256qam_fs24m`
possui os seguintes parâmetros principais:

| Parâmetro | Valor |
|---|---|
| Padrão de referência | ATSC 3.0 / A/322 |
| Canal | 6 MHz |
| FFT | 8K |
| Modulação | 256-QAM |
| Code rate | 9/15 |
| Guard interval | 5/1024 |
| Pilot pattern | SP3_4 |
| Taxa nativa do flowgraph | 6,912 MS/s |
| Taxa final para DPD/HDL | 24 MS/s |
| Razão de reamostragem | 125/36 |
| Número de amostras | 262144 |
| PAPR medido | aproximadamente 10,33 dB |

O reamostramento para 24 MS/s foi adotado para manter quatro vezes a largura de
canal de 6 MHz. Essa relação é importante para o estudo de DPD, pois permite
observar componentes de distorção fora da banda útil e evita que o sinal de
validação fique subamostrado para análise de não linearidades.

---

# Conversão para os Ambientes de Validação

A saída complexa do GNU Radio é usada como referência comum para duas frentes de
trabalho. No OpenDPD, ela alimenta o treinamento do PA e do predistorter. No HDL,
ela é convertida para arquivos `.hex` em Q1.15, permitindo que os testbenches
reproduzam exatamente a mesma sequência de amostras.

Os arquivos principais gerados para o HDL são:

```text
ref_iq_q15.hex
feedback_iq_q15.hex
expected_capture_hi_delay0.hex
expected_capture_lo_delay0.hex
```

Em hardware real, o feedback será produzido pela cadeia de observação do PA. No
ambiente de simulação, o arquivo de feedback é mantido para tornar o experimento
determinístico e permitir comparação ciclo a ciclo.
