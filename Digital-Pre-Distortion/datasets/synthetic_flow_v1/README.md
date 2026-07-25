# synthetic_flow_v1

Dataset sintetico pequeno para a primeira validacao do fluxo completo do DPD:

```text
bypass -> capture -> leitura AXI-Lite da capture RAM -> escrita de coeficientes
       -> request switch -> sync_event -> DPD active -> IRQ/retrain
```

## Contrato

- Formato numerico: I/Q signed 16-bit, Q1.15 nominal.
- Canal alvo: baseband complexo para fluxo de 6 MHz; este dataset nao e OFDM real, e apenas vetor deterministico inicial.
- `sample_valid` e `feedback_valid` devem ficar altos continuamente durante o burst.
- `ref_iq_q15.hex`: uma palavra por amostra, `{I[15:0], Q[15:0]}`.
- `feedback_iq_q15.hex`: uma palavra por amostra, `{I[15:0], Q[15:0]}`.
- `samples.csv`: versao legivel das mesmas amostras.
- `expected_capture_delay0.csv`: expectativa de captura para o `delay_align` atual com `feedback_delay = 0`.
- `expected_capture_hi_delay0.hex`: palavras esperadas em `CAPTURE_RD_HI`.
- `expected_capture_lo_delay0.hex`: palavras esperadas em `CAPTURE_RD_LO`.

## Observacao de alinhamento

O bloco `delay_align` registra o feedback. Com burst continuo e `feedback_delay = 0`, a captura efetiva observa REF da amostra corrente e FB da amostra anterior. Por isso `expected_capture_delay0.csv` comeca em `source_index = 1`.

## Uso sugerido no primeiro RUN

1. Configurar `DPD_DELAY_CTRL = 0`.
2. Configurar `DPD_CAPTURE_CTRL = 15` para capturar 16 pares validos.
3. Acionar `DPD_CONTROL = FORCE_BYPASS | CAPTURE`.
4. Alimentar as primeiras 17 linhas de `ref_iq_q15.hex` e `feedback_iq_q15.hex` com valid continuo.
5. Ler `CAPTURE_RD_ADDR = 0..15` via AXI-Lite.
6. Comparar `CAPTURE_RD_HI/LO` com `expected_capture_delay0.csv`.

## Testbench automatico

O testbench `tb/tb_dpd_top_dataset_manual.sv` le os arquivos `.hex` com `$readmemh` e executa:

```text
dataset capture -> leitura AXI-Lite da capture RAM -> escrita bank B
                -> switch sincronizado -> metricas -> retrain
```

Na GUI do Questa:

```tcl
vlog -work work -f rtl/filelist.f
vlog -sv -work work tb/tb_dpd_top_dataset_manual.sv
vsim work.tb_dpd_top_dataset_manual
run -all
```
