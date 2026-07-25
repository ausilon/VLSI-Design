# Estado Técnico do Projeto

O projeto já possui uma cadeia de validação completa o suficiente para discutir
arquitetura, desempenho e custo físico dos blocos principais. A implementação
HDL foi validada em simulação, os datasets foram padronizados e a preparação
OpenLane forneceu estimativas de área e timing para os macros mais importantes.

---

# Etapas Concluídas

O dataset ATSC 3.0/A/322 foi gerado com GNU Radio a partir do projeto
`gr-atsc3`, usando o exemplo `vv031.grc` como base. O sinal foi exportado em
banda-base complexa, reamostrado para 24 MS/s e convertido para os formatos
OpenDPD e HDL.

O OpenDPD foi usado para modelar o PA, treinar o predistorter e gerar
coeficientes GMP. Os coeficientes foram exportados para Q2.16 e usados na
validação do `GMPengine`.

No HDL, foram validados separadamente `GMPengine`, `MetricEngine` e `MACcore`.
Depois disso, o `dpd_top` foi simulado em fluxo completo, incluindo bypass,
captura, treinamento, escrita de coeficientes, troca de banco, ativação do DPD e
pedido de retreinamento.

No OpenLane, os blocos menores chegaram a DRC/LVS limpos. RAM de captura e banco
de coeficientes foram preparados com SRAM hard macros. O top-level físico foi
montado como scaffold para estudar área e distribuição das macros.

---

# Gargalo Atual

O principal ponto técnico em aberto é o fechamento de timing do `GMPengine`.
Para reduzir área, a versão física atual executa uma amostra em quatro ciclos.
Com essa arquitetura, 24 MS/s exige clock mínimo de 96 MHz. A rodada física
preliminar indicou aproximadamente 90,9 MHz, portanto o bloco está próximo do
alvo, mas ainda sem margem.

A estratégia em andamento é tentar uma rodada mais agressiva de síntese,
placement, CTS e resizer com alvo de 9 ns. Se essa tentativa não fechar, a
alternativa mais direta é reduzir o intervalo de iniciação do `GMPengine` para
três ciclos por amostra, aceitando aumento moderado de área.

---

# Próximos Passos

O próximo avanço técnico é concluir a tentativa de timing do `GMPengine` acima
de 96 MHz. Em seguida, o top-level deve ser transformado de scaffold físico para
chip funcional conectado, com padframe, IOs essenciais, PDN revisado, roteamento
de sinais, LVS completo e STA de chip.

Também é necessário revisar a documentação do artigo para refletir os números
finais de timing e área. A seção de conclusão deve separar claramente o que foi
validado em simulação, o que foi medido fisicamente em SKY130 e o que permanece
como trabalho futuro.
