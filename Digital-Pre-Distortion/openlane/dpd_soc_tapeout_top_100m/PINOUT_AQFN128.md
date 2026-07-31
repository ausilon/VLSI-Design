# Pinout logico do DPD SoC

## Alvo de encapsulamento

O alvo eletrico e um encapsulamento leadless de 128 terminais, com exposed pad
ligado a `VSSD/GND`. O nome correto da familia e `aQFN/DRQFN-128` multi-row.
Um QFN convencional 9 x 9 mm normalmente nao oferece essa contagem de
terminais; por isso, dimensao externa, paddle, pitch, numeracao e limite de die
permanecem condicionados ao desenho mecanico de um OSAT selecionado.

Essa ressalva impede liberar agora um bonding diagram definitivo, mas nao impede
congelar o contrato eletrico de 128 terminais.

## Contrato eletrico congelado

| Grupo | Direcao | Quantidade | Observacao |
|---|---|---:|---|
| `ref_i[15:0]`, `ref_q[15:0]` | entrada | 32 | referencia complexa Q1.15 |
| `fb_i[15:0]`, `fb_q[15:0]` | entrada | 32 | realimentacao complexa Q1.15 |
| `out_i[15:0]`, `out_q[15:0]` | saida | 32 | saida complexa predistorcida Q1.15 |
| `clk`, `resetn` | entrada | 2 | clock e reset do chip |
| `sample_valid`, `out_ready` | entrada | 2 | handshake de entrada/saida |
| `sample_ready`, `out_valid` | saida | 2 | handshake de entrada/saida |
| `flash_sck`, `flash_mosi`, `flash_cs` | saida | 3 | flash SPI de firmware |
| `flash_miso` | entrada | 1 | flash SPI de firmware |
| `uart_rx` | entrada | 1 | configuracao e diagnostico |
| `uart_tx` | saida | 1 | configuracao e diagnostico |
| `test_mode`, `scan_clk`, `scan_in` | entrada | 3 | reserva DFT |
| `scan_out` | saida | 1 | reserva DFT |
| `VCCD`, `VSSD` | alimentacao | 8 | quatro terminais de cada rede de core |
| `VDDIO`, `VSSIO` | alimentacao | 4 | dois terminais de cada rede de IO |
| `VDDA`, `VSSA` | alimentacao | 4 | dois terminais de cada rede analogica/ESD |
| **Total** |  | **128** | exposed pad adicional em `VSSD/GND` |

Os GPIOs digitais adotam sinalizacao CMOS de `1.8 V`, com `VCCD=1.8 V` e
`VDDIO=1.8 V`. O pad candidato para sinais digitais e
`sky130_fd_io__top_gpiov2`; reset, clamps, corners, fillers e pads de
alimentacao devem vir da mesma biblioteca `sky130_fd_io`. A liberacao final
depende de STA com carga do encapsulamento e da placa, pois o barramento de
saida opera a aproximadamente 25 MHz.

## Sinais deliberadamente internos

Os sete sinais abaixo nao recebem pad nem terminal no encapsulamento:

1. `dbg_spi_sck`
2. `dbg_spi_mosi`
3. `dbg_spi_miso`
4. `dbg_spi_cs`
5. `irq`
6. `retrain_request`
7. `trap`

O SPI de debug secundario sera desabilitado internamente. `irq`,
`retrain_request` e `trap` continuam disponiveis para a logica interna e para
observabilidade por registradores/UART, sem copias dedicadas no padframe.

Estado de implementacao: o top HDL e o `pin_order.cfg` ja foram reduzidos de
115 para 108 sinais funcionais externos. A hierarquia foi validada no Yosys. Os
quatro sinais DFT continuam reservados no orcamento, mas nao foram adicionados
ao HDL porque a arquitetura de scan ainda nao esta definida.

## Fontes de engenharia

- [SkyWater SKY130 I/O user guide](https://skywater-pdk.readthedocs.io/en/main/contents/libraries/sky130_fd_io/docs/user_guide.html)
- [ASE leadframe packages: QFN, DRQFN e aQFN](https://asekh.aseglobal.com/products-services/lead-frame.html)
- [JCET QFN package family](https://www.jcetglobal.com/uploads/QFN_22Dec2021.pdf)

## Pendencia mecanica

Antes do padframe final deve ser selecionado um part number/package outline de
OSAT que aceite o die estimado, 128 terminais, exposed pad e dissipacao do SoC.
Somente esse desenho pode congelar numeracao de pinos, coordenadas de bond pads,
bond-wire e dimensoes externas. Nao se deve rotular o projeto como
`QFN-128 9x9` sem essa confirmacao.
