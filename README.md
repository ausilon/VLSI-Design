# VLSI-Design

Repositório do projeto final do curso de **Residência em TIC 41 – Programa de Desenvolvimento de Competências em Sistemas Digitais (Programa CI Digital)**.  
O objetivo deste projeto é desenvolver e validar técnicas de design de sistemas digitais para sinais OFDM, incluindo modelagem de amplificadores e otimização de algoritmos de pre-distorsão digital (DPD).

## Passos do Projeto

1. **Criar dataset baseband complexo OFDM personalizável com GNU Radio**  
   Desenvolver um conjunto de sinais OFDM que possa ser ajustado em parâmetros como número de subportadoras, modulação e taxa de amostragem, utilizando o GNU Radio.

2. **Usar scripts Python para realizar a validação inicial**  
   Validar a integridade do dataset e verificar a conformidade dos sinais gerados com as especificações do projeto, usando scripts automatizados em Python.

3. **Criar um modelo de amplificador distorcido**  
   Modelar matematicamente o comportamento de um amplificador não linear que introduz distorção nos sinais OFDM, preparando o sistema para simulações de pre-distorsão.

4. **Encontrar o melhor algoritmo e parâmetros com openDPD**  
   Aplicar técnicas de pre-distorsão digital utilizando o openDPD, ajustando parâmetros para minimizar a distorção do sinal e maximizar a eficiência do amplificador.

5. **Iniciar desenvolvimento HDL**  
   Implementar partes do sistema em **HDL (VHDL ou Verilog)** para futuras sínteses em FPGA ou ASIC, com foco em processamento digital de sinais em tempo real.

## Tecnologias Utilizadas

- **GNU Radio** – geração e manipulação de sinais OFDM  
- **Python** – scripts de validação e análise de dados  
- **openDPD** – otimização de pre-distorsão digital  
- **HDL (VHDL/Verilog)** – implementação de hardware digital  

## Estrutura do Repositório
