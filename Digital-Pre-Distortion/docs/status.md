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

No OpenLane, o `GMPengine` e o `MACcore` foram transformados em hard macros
serializadas. RAM de captura e banco de coeficientes usam SRAM hard macros e
foram refeitos para fechamento temporal em 100 MHz. O top-level atual já possui
conectividade funcional, FIFOs de fronteira, PDN hierárquica e um contrato de
pinout para 128 terminais.

---

# Gargalo Atual

O gargalo imediato é concluir o hardening do `MACcore` atualizado e executar o
top com todas as views coerentes. O candidato `mac_core_100m_05` apresenta em
global-route setup de `+1,47 ns`, hold de `+0,16 ns`, 131.048 células e
7,659 mm². O primeiro detailed routing terminou com um único short em met1; a
continuação parte do checkpoint pós-global-route e não repete síntese,
floorplan, placement ou CTS.

O `GMPengine` já opera com `II=4`, dez lanes e clock alvo de 100 MHz, atendendo
25 MS/s. Seu resultado preservado apresenta setup de `+3,16 ns` e hold de
`+0,09 ns` no global-route, além de DRC/LVS limpos. Ainda é necessário produzir
STA RCX multicorner para consolidar o fechamento temporal do bloco.

A Capture RAM fecha setup/hold em `+1,27/+0,01 ns`, e o Coef Bank em
`+0,16/+0,82 ns`, ambos em STA pós-route multicorner. As margens são positivas,
mas o hold da Capture RAM é estreito e deve ser acompanhado na integração.

---

# Próximos Passos

1. concluir DRC/LVS do `mac_core_100m_05`;
2. instalar no top os LEF/LIB/GDS atuais do MACcore, Capture RAM e Coef Bank;
3. executar `top_v4_memfix_100m_01` com STA, DRC, antena, LVS e XOR estritos;
4. implementar o padframe com `sky130_fd_io` para o contrato
   `aQFN/DRQFN-128`;
5. executar STA RCX multicorner, potência, IR drop, CVC/ERC e simulação
   gate-level com SDF;
6. atualizar artigo e tabela física somente com resultados auditados.

Até essas etapas terminarem, os números de global-route são apresentados como
resultados físicos preliminares, e o top não é classificado como GDS pronto
para foundry.
