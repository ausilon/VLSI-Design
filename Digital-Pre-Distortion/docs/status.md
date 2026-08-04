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
As revisões serializadas usadas pelo OpenLane também possuem validação golden
independente: o GMP físico reproduziu 64 saídas I/Q bit-exatas do OpenDPD, e o
MACcore físico reproduziu checkpoints e coeficientes de um golden NLMS de
software. Depois disso, o `dpd_top` funcional foi simulado em fluxo completo,
incluindo bypass, captura, treinamento, escrita de coeficientes, troca de banco,
ativação do DPD e pedido de retreinamento.

Essa integração conjunta foi efetivamente executada no `simv2`. O
`tb_dpd_top_gmp_metric_integration` passou com RAM/banco A, golden OpenDPD e
métricas integradas; o `tb_dpd_top_full_system` passou com RAM de captura,
treinamento, bancos A/B, troca sincronizada, métricas, IRQ e retreinamento. Esse
item está fechado para a revisão funcional `rtl_v2`.

Esses resultados não equivalem ainda a uma regressão conjunta do top usando as
duas revisões físicas. A limitação restante do RTL está na consolidação das
interfaces, latências e testbenches em uma única baseline, e não na ausência de
referência numérica para os motores DSP.

No OpenLane, o `GMPengine` e o `MACcore` foram transformados em hard macros
serializadas. RAM de captura e banco de coeficientes usam SRAM hard macros e
foram refeitos para fechamento temporal em 100 MHz. O top-level atual já possui
conectividade funcional, FIFOs de fronteira, PDN hierárquica e um contrato de
pinout para 128 terminais.

---

# Gargalo Atual

As oito macros possuem síntese mapeada, CTS, global routing e STA single-corner
pós-global-route a 100 MHz. Esse é o checkpoint comum usado para comparar área,
contagem de células e slack. Resultados posteriores existem para alguns blocos,
mas não são tratados como signoff uniforme enquanto constraints, STA RCX
multicorner, DRC, LVS e antena não forem comprovados no mesmo nível.

O `top_v4_clean_50m_01` gerou os artefatos iniciais de integração a 50 MHz,
incluindo GDSII e SPEF. Seu STA RCX multicorner ainda é negativo, com pior setup
de `-4,74 ns` e pior hold de `-1,82 ns`; portanto, ele permanece uma integração
física experimental para orientar as próximas iterações.

---

# Próximos Passos

1. portar a regressão conjunta já aprovada no `simv2` para um top com as
   revisões OpenLane golden do GMPengine e MACcore e com as interfaces atuais
   de RAM, bancos e métricas;
2. resolver a duplicidade entre `HDL/rtl` e as variantes físicas, congelando a
   composição aprovada como implementação HDL canônica;
3. congelar os hashes do RTL, datasets e testbenches dessa baseline;
4. tratar os resultados OpenLane existentes como avaliação física experimental
   até existir um conjunto uniforme de runs completos;
5. concluir STA, DRC, LVS e antena das macros e do top sem exceções abertas;
6. implementar o padframe com `sky130_fd_io` para o contrato
   `aQFN/DRQFN-128`;
7. executar STA RCX multicorner, potência, IR drop, CVC/ERC e simulação
   gate-level com SDF;
8. atualizar artigo e tabela física somente com resultados auditados.

Até essas etapas terminarem, os números de global-route são apresentados como
resultados físicos preliminares, e o top não é classificado como GDS pronto
para foundry.
