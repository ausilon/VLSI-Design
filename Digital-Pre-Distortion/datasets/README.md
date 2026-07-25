# Datasets

Este diretório contém apenas datasets selecionados para reprodução. Datasets
intermediários grandes e experimentais ficam fora do repositório.

## Incluídos

| Dataset | Uso |
|---|---|
| `synthetic_flow_v1` | smoke test do fluxo RTL completo |
| `opendpd_coeffs` | coeficientes e vetores pequenos para validar o GMPengine |
| `atsc3_a322_vv031_8k_256qam_fs24m` | baseband alvo ATSC 3.0/A/322 em 24 Msps |

## Formatos

| Arquivo | Descrição |
|---|---|
| `ref_iq_q15.hex` | amostras de referência I/Q em Q1.15 |
| `feedback_iq_q15.hex` | feedback distorcido/gerado para validação |
| `expected_capture_hi_delay0.hex` | palavra alta esperada da captura |
| `expected_capture_lo_delay0.hex` | palavra baixa esperada da captura |
| `*_complex64.bin` | IQ complexo float32 para uso em Python/OpenDPD |
| `*_iq16.bin` | IQ intercalado int16 |
| `metadata.json` | metadados do dataset |

## Nota Técnica

Em hardware real, o feedback não é um arquivo de entrada estático. Ele vem do PA
e da cadeia de conversão/observação. Nos testbenches, `feedback_iq_q15.hex` é
mantido para reproduzir o contrato REF/FB de forma determinística.
