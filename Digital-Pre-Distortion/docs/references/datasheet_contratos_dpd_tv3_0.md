# Datasheet preliminar - Contratos DPD para TV 3.0 / DTV+

Data: 2026-06-22

Escopo: contratos de interface e validacao para o DPD digital em ASIC SKY130, considerando transmissores brasileiros TV 3.0/DTV+.

## 1. Perfil do sistema alvo

| Item | Especificacao preliminar | Obrigatorio para o DPD? | Impacto no RTL | Fonte |
|---|---:|---|---|---|
| Sistema alvo | TV 3.0 / DTV+ | Sim | Define familia de waveform e requisitos de validacao | SBTVD OG-01, ABNT NBR 25601 |
| Camada fisica base | ATSC 3.0 PHY / ATSC A/322 | Sim | DPD deve tratar OFDM de alta PAPR, PLPs, LDM/MIMO | SBTVD OG-01, ATSC A/322 |
| Canal brasileiro inicial | 6 MHz | Sim | Dataset e analise espectral devem usar mascara/ocupacao de 6 MHz | SBTVD reports, regulacao local |
| Faixa RF citada no guia | 44 MHz a 960 MHz | Nao no RTL baseband | RTL deve ser independente da RF; DUC/DAC/PA ficam fora | SBTVD OG-01 |
| Larguras suportadas pela PHY | 6, 7 ou 8 MHz | Parametrico | Nao fixar constantes de taxa no RTL | SBTVD OG-01 / A/322 |
| Bootstrap | Sempre presente; ocupa 4,5 MHz e usa IFFT 2K | Indireto | DPD deve preservar espectro/linearidade tambem no bootstrap | SBTVD OG-01 / A/321 |
| FFT de dados | 8K, 16K ou 32K | Indireto | Dataset deve informar FFT; DPD nao precisa conhecer FFT se receber I/Q final | SBTVD OG-01 / A/322 |
| Guard Interval | Parametrico conforme FFT/cenario | Indireto | Latencia DPD deve ser constante e rastreavel | SBTVD OG-01 / A/322 |
| PLP | Um ou multiplos Physical Layer Pipes | Indireto | Metricas devem funcionar com qualquer mistura de PLPs | A/322 |
| LDM | Suportado/recomendado para protecao desigual | Sim para produto futuro | Aumenta PAPR; validar com single-layer e dual-layer | SBTVD OG-01 / A/322 |
| MIMO | MIMO 2x2 validado em relatorios SBTVD | Sim para arquitetura futura | Prever uma instancia DPD por cadeia PA/polarizacao | SBTVD P3 PL reports |
| Layered MIMO | Tipos A e B citados | Futuro | Pode exigir dois DPDs correlacionados, um por TX chain | SBTVD OG-01 / A/322 |
| TxID | Identificador de transmissor de 13 bits | Indireto | DPD nao gera TxID, mas deve nao degradar medicao/SFN | SBTVD OG-01 |

## 2. Contrato de entrada e saida I/Q

| Item | Valor recomendado agora | Valor futuro/parametrico | Impacto no RTL |
|---|---:|---:|---|
| Interface de amostra | Stream I/Q baseband complexo | Mantido | `valid/ready` obrigatorio |
| Palavra de entrada | 32 bits | Parametrico | `I[15:0]` + `Q[15:0]` |
| Representacao I/Q externa | signed two's complement | Mantido | Evita conversao interna |
| Largura efetiva inicial | 12 a 14 bits uteis dentro de 16 bits | Ajustavel por escala | Melhor compromisso SKY130 |
| Largura interna do sample | 16 bits hoje | 12/14/16 via parametro | Manter `SAMPLE_WIDTH` parametrico |
| Saida DPD | Mesmo formato da entrada | Mantido | Facilita bypass e comparacao |
| Sincronismo | `sample_valid_in`, `sample_ready_out`, `sample_valid_out`, `sample_ready_in` | Mantido | Ja usado no `dpd_filter` |
| Latencia | Constante quando DPD ativo | A definir apos GMP | Necessario para REF/FB e comparacao |
| Bypass | Sem alteracao de amostra | Obrigatorio | Bring-up, falha segura e coleta inicial |
| Saturacao | Saturacao aritmetica, nao wrap | Obrigatorio no GMP real | Ainda falta implementar |
| Escala | Dataset deve informar full-scale e RMS | Obrigatorio para treino | Evita coeficientes inconsistentes |

## 3. Contrato de captura e treinamento

| Item | Especificacao preliminar | Status atual | Proxima decisao |
|---|---|---|---|
| Inicio do sistema | Bypass ativo | Implementado | Manter como default seguro |
| Fonte de treino | REF I/Q + FB I/Q alinhados | Captura shell implementada | Expor leitura da RAM |
| Captura | Ping-pong RAM | Implementado sem porta de leitura CPU | Adicionar read port AXI/firmware |
| Validacao REF/FB | Requer stream continuo ou sinais alinhados | Confirmado em TB | Criar TB com atraso conhecido |
| Delay align | Delay programavel 0-255 amostras | Implementado | Futuro: estimador/adaptativo |
| Tempo de treino | 1 a 5 minutos aceitavel | Arquitetural | Treino pode ser serial/lento |
| Treinador | Firmware/PicoRV32 ou FSM lenta | Nao implementado | Comecar em software/testbench |
| Atualizacao de coeficientes | Banco inativo recebe novos pesos | Implementado | Definir protocolo de commit |
| Troca de coeficientes | Apenas em `sync_event` e datapath idle | Implementado e validado | Manter |
| Re-treino | Disparo por metricas/threshold | Placeholder validado | Definir metricas reais |

## 4. Contrato GMP / DPD core

| Item | Valor inicial recomendado | Motivo | Status |
|---|---:|---|---|
| Modelo | GMP reduzido | Justificavel com OpenDPD e padrao industrial | Nao implementado |
| Ordem nao linear inicial | 3 ou 5 | Controle de area/multiplicadores | A definir |
| Memoria principal | 3 a 5 taps | Bom ponto inicial para PA com memoria moderada | A definir |
| Cross terms | 1 a 2 offsets | Evita explosao combinatoria | A definir |
| Coeficientes | 16 a 18 bits signed | Compatibilidade com RTL atual `COEF_WIDTH=18` | Parcial |
| Acumulador | 40 a 48 bits | Necessario para soma GMP sem overflow | Nao implementado |
| Basis | usar `|x|^2 = I^2 + Q^2` | Evita sqrt | Nao implementado |
| MAC | Pipelineado no fast path | Throughput continuo | Placeholder |
| History buffer | Tapped delay line I/Q | Necessario para GMP | Nao implementado |
| Pruning | Termos podados por OpenDPD | Reduz area/potencia | Futuro |
| Bypass interno | Mux sincronizado | Ja existe no `dpd_filter` | Implementado |

## 5. Contrato de metricas

| Metrica | Uso | Implementacao atual | Requisito futuro |
|---|---|---|---|
| Potencia media | Monitorar nivel e escala | Placeholder inteiro | RMS/janela configuravel |
| Erro REF-FB | Trigger de re-treino | Placeholder absoluto | NMSE ou proxy correlacionado |
| Clipping | Detectar saturacao | Threshold fixo simples | Threshold configuravel por escala |
| Drift | Mudanca rapida do erro | Placeholder | Deriva em janela temporal |
| ACLR/shoulder | Validacao RF/espectral | Ausente | Pode ser offline no dataset inicialmente |
| EVM | Qualidade de modulacao | Ausente | Offline inicialmente |
| PAPR | Risco para PA e DPD | Ausente | Medir no dataset/testbench |

## 6. Contrato para dataset GNU Radio

| Campo de metadado | Obrigatorio? | Exemplo/valor esperado |
|---|---|---|
| `standard` | Sim | `TV3.0_DTV+` |
| `phy_reference` | Sim | `ABNT_NBR_25601_ATSC_A322` |
| `channel_bw_hz` | Sim | `6000000` |
| `sample_rate_hz` | Sim | definido pelo flow GNU Radio |
| `iq_format` | Sim | `sc16_le`, `float32_complex`, etc. |
| `iq_scale` | Sim | full-scale e RMS |
| `fft_size` | Sim | `8192`, `16384`, `32768` |
| `guard_interval` | Sim | valor ou fracao GI |
| `mimo_mode` | Sim | `SISO`, `MIMO_2x2`, `Layered_MIMO_A/B` |
| `ldm_enabled` | Sim | `true/false` |
| `plp_count` | Sim | numero de PLPs |
| `papr_reduction` | Desejavel | algoritmo/config se usado |
| `tx_chain_id` | Sim para MIMO | `0` ou `1` |
| `ref_file` | Sim | I/Q antes do PA |
| `fb_file` | Sim | I/Q realimentado apos PA/ADC |
| `delay_samples` | Desejavel | atraso conhecido/estimado |
| `pa_conditions` | Desejavel | potencia, temperatura, ganho |

## 7. Requisitos para SKY130

| Item | Diretriz | Justificativa |
|---|---|---|
| Float | Nao usar | Area/potencia inviaveis |
| Fixed-point | Obrigatorio | Adequado a ASIC |
| Multiplicadores | Minimizar paralelismo | Dominam area/potencia |
| Treino | Serial/lento | Atualizacao de 1-5 min permite baixa area |
| Fast path | Pipelineado | Deve sustentar stream continuo |
| Clock alvo inicial | 25 a 50 MHz | Folga para 24 Mbps em palavras de 32 bits |
| MIMO futuro | DPD por cadeia | Evita misturar PAs distintos |
| OpenLane | Usar apos RTL funcional | Sintese antes do GMP real mede pouco |

## 8. Decisoes abertas

| Decisao | Opcoes | Recomendacao inicial |
|---|---|---|
| Ordem GMP | 3, 5, 7 | comecar em 5 |
| Taps memoria | 3, 5, 7 | comecar em 3 ou 5 |
| Cross terms | 0, 1, 2, 3 | comecar em 1 |
| Largura I/Q real | 12, 14, 16 bits | 14 bits se area permitir |
| Coeficientes | 16 ou 18 bits | manter 18 bits inicialmente |
| Acumulador | 40, 44, 48 bits | 48 bits para sim, reduzir depois |
| Captura | AXI read direto ou DMA simples | AXI read direto primeiro |
| Metricas HW | simples ou completas | simples no RTL, EVM/ACLR offline |

## 9. Fontes locais principais

- `SBTVD-TV3.0-OG-01-Physical-Layer.pdf`
- `SBTVD-TV_3_0-P3-PL-Field-Report.pdf`
- `SBTVD-TV_3_0-P3-PL-Lab-Report.pdf`
- `ATSC-A322-2024-09-Physical-Layer-Protocol.pdf`
- `abnt_catalogo_NBR_25601.html`
- `referencias_tv3_0.bib`
