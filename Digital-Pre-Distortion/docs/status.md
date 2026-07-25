# Estado Técnico

## Classificação do Projeto

O projeto está no estágio de prova de conceito avançada. Ele já cobre uma cadeia
ampla, desde datasets e treinamento até HDL e avaliação física preliminar, mas
ainda não é um circuito integrado pronto para fabricação.

Essa classificação é importante para a apresentação: o valor técnico está em
mostrar que a arquitetura é coerente, que os blocos críticos foram validados e
que os gargalos físicos foram medidos. O trabalho ainda não afirma fechamento
industrial completo de timing, padframe, LVS/STA final ou qualificação para
foundry.

Ferramentas usadas:

- GNU Radio, Python e OpenDPD para sinal, modelo e treinamento;
- Questa Intel FPGA Edition para simulação HDL;
- OpenLane/OpenROAD/Yosys/Magic/KLayout e SKY130 para avaliação física.

## Validado

- Geração de datasets OFDM/ATSC 3.0 para validação.
- Treinamento OpenDPD para referência algorítmica.
- Exportação de coeficientes Q2.16.
- Validação do `GMPengine` contra vetores golden.
- Validação do `MetricEngine`.
- Validação do `MACcore` NLMS serializado.
- Teste integrado de `dpd_top` com bypass, captura, treino, troca de banco e
  retreinamento.
- Macros menores OpenLane com DRC/LVS limpos.
- Scaffold físico top-level com Magic DRC limpo.

## Em Aberto

- Fechar margem do `GMPengine` para 24 Msps em modo DPD ativo.
- Criar top funcional completamente conectado.
- Definir padframe e contrato de IO/alimentação.
- Fechar PDN, roteamento, antena, LVS e STA do chip completo.
- Revisar documentação final do artigo.

## Gargalo Atual

O `GMPengine` OpenLane serializado usa 4 ciclos por amostra. O resultado físico
preliminar ficou em aproximadamente 90,9 MHz, equivalente a 22,7 Msps. O alvo de
24 Msps exige no mínimo 96 MHz.

Está em andamento uma tentativa de fechamento mais agressiva com alvo de 9 ns
(111,1 MHz), sem alterar o HDL funcional nem o floorplan conceitual.
