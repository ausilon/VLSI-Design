# Datasets

Os datasets deste diretório foram selecionados para permitir reprodução dos
testes principais sem carregar todo o histórico experimental. Eles representam
os sinais usados para validar o contrato entre GNU Radio, OpenDPD e HDL.

O dataset mais importante é `atsc3_a322_vv031_8k_256qam_fs24m`. Ele foi gerado a
partir do flowgraph GNU Radio descrito em `../gnu-radio`, usando como referência
o exemplo `vv031.grc` do projeto `gr-atsc3`. A saída complexa foi normalizada,
reamostrada para 24 MS/s e convertida para os formatos usados no OpenDPD e nos
testbenches.

O dataset `opendpd_coeffs` contém coeficientes exportados de um treinamento
OpenDPD. Ele é usado para validar se o `GMPengine` em HDL reproduz a saída
esperada para um conjunto pequeno de amostras. O dataset `synthetic_flow_v1` é
menor e serve como teste rápido do fluxo de captura, leitura e troca de bancos.

---

# Estrutura dos Arquivos

| Arquivo | Função |
|---|---|
| `*_complex64.bin` | sinal I/Q em float complexo para Python/OpenDPD |
| `*_iq16.bin` | sinal I/Q intercalado em inteiros de 16 bits |
| `*_q15_262144.hex` | sinal Q1.15 em formato hexadecimal |
| `ref_iq_q15.hex` | entrada de referência dos testbenches |
| `feedback_iq_q15.hex` | feedback determinístico para simulação |
| `expected_capture_hi_delay0.hex` | metade alta esperada da RAM de captura |
| `expected_capture_lo_delay0.hex` | metade baixa esperada da RAM de captura |
| `metadata.json` | descrição do dataset e parâmetros de conversão |
| `baseband_metadata.json` | parâmetros do sinal ATSC 3.0 gerado |

---

# Uso nos Testbenches

Os nomes dos arquivos foram mantidos iguais entre datasets para permitir que a
simulação seja redirecionada apenas trocando o diretório de entrada. Isso foi
útil durante a validação, pois o mesmo testbench pôde ser executado com dataset
sintético, dataset DVB-T2 intermediário e dataset ATSC 3.0 final.

No sistema real, o fluxo de feedback não virá de arquivo. Ele será amostrado
após o PA e a cadeia de observação. O arquivo `feedback_iq_q15.hex` existe
somente para simulação reprodutível.
