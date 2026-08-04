# Trabalhos Futuros

Este documento concentra atividades prospectivas do projeto. Os itens abaixo
não representam resultados concluídos nem evidência de signoff; o estado
comprovado permanece descrito em [status.md](status.md).

## Baseline HDL Canônica

1. adaptar a regressão conjunta aprovada no `simv2` para um top que instancie
   exatamente as revisões serializadas do GMPengine e do MACcore;
2. conciliar interfaces e latências entre essas revisões, a Capture RAM, os
   bancos de coeficientes e o MetricEngine;
3. congelar os hashes do RTL, datasets e testbenches depois da aprovação da
   regressão canônica.

## Fechamento Físico

1. executar as oito macros com constraints completas e um fluxo uniforme de
   STA RCX multicorner, DRC, LVS, XOR e antena;
2. integrar as views aprovadas no top e fechar setup e hold no clock adotado
   para cada domínio;
3. repetir as verificações no top sem exceções ou checks desabilitados.

## Integração do Chip

1. implementar o padframe com `sky130_fd_io` para o contrato de encapsulamento
   `aQFN/DRQFN-128`;
2. dimensionar a rede de alimentação a partir de atividade de comutação
   representativa e executar análises de potência, IR drop e integridade;
3. executar CVC/ERC e simulação gate-level com atrasos SDF.

## Validação Experimental

1. ampliar a caracterização com diferentes janelas do dataset ATSC 3.0 e
   diferentes condições do PA;
2. medir convergência, estabilidade e seleção do melhor modelo durante o
   treinamento interno;
3. validar a arquitetura em FPGA e, quando disponível, em uma cadeia de RF com
   feedback real do amplificador de potência.

## Documentação Acadêmica

Os resultados devem ser incorporados ao artigo somente depois de auditados. Na
versão final do manuscrito, os itens ainda abertos podem ser resumidos em uma
subseção de trabalhos futuros associada à conclusão.
