// Interface-only hard macros appear undriven to an RTL linter by construction.
`ifdef VERILATOR_LINT
/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off UNDRIVEN */
/// sta-blackbox
(* blackbox *) module picorv32_ol_wrapper (
    input wire clk, input wire resetn, input wire mem_ready, input wire [31:0] mem_rdata,
    input wire [31:0] irq, output wire trap, output wire mem_valid, output wire mem_instr,
    output wire [31:0] mem_addr, output wire [31:0] mem_wdata, output wire [3:0] mem_wstrb,
    output wire [31:0] eoi
); endmodule

(* blackbox *) module gmp_engine_ol_wrapper (
    input wire clk, input wire resetn, input wire enable_i, input wire reload_coeffs_i,
    input wire signed [15:0] sample_i_i, input wire signed [15:0] sample_q_i,
    input wire in_valid_i, input wire out_ready_i, input wire signed [17:0] coef_data_i,
    output wire in_ready_o, output wire signed [15:0] sample_i_o,
    output wire signed [15:0] sample_q_o, output wire out_valid_o,
    output wire [6:0] coef_addr_o, output wire busy_o
); endmodule

(* blackbox *) module capture_ram_macro (
    input wire clk, input wire resetn, input wire start, input wire [9:0] capture_len,
    input wire signed [15:0] ref_i, input wire signed [15:0] ref_q,
    input wire signed [15:0] fb_i, input wire signed [15:0] fb_q,
    input wire sample_valid, input wire snapshot_lock, input wire [9:0] rd_addr,
    output wire [63:0] rd_data, output wire busy, output wire done,
    output wire snapshot_page, output wire capture_ready
); endmodule

(* blackbox *) module coef_bank_macro (
    input wire clk, input wire resetn,
    input wire cpu_we_a, input wire cpu_we_b, input wire [6:0] cpu_addr,
    input wire [17:0] cpu_wdata, output wire [17:0] cpu_rdata_a,
    output wire [17:0] cpu_rdata_b,
    input wire train_we_a, input wire train_we_b, input wire [6:0] train_addr,
    input wire [17:0] train_wdata, input wire [6:0] mac_addr,
    output wire [17:0] mac_rdata_a, output wire [17:0] mac_rdata_b
); endmodule

(* blackbox *) module mac_engine (
    input wire clk, input wire resetn, input wire train_start, input wire capture_done,
    input wire [9:0] train_sample_count, output wire capture_lock,
    output wire capture_release, output wire mac_rd_en, output wire [9:0] mac_rd_addr,
    input wire [63:0] mac_rd_data, output wire train_busy, output wire train_done,
    output wire train_error, output wire coef_ready, output wire coef_we,
    output wire [6:0] coef_addr, output wire signed [17:0] coef_wdata,
    output wire [31:0] status_error_acc
); endmodule

(* blackbox *) module metric_engine (
    input wire clk, input wire resetn, input wire clear,
    input wire signed [15:0] ref_i, input wire signed [15:0] ref_q,
    input wire signed [15:0] fb_i, input wire signed [15:0] fb_q,
    input wire sample_valid, input wire signed [15:0] dpd_i,
    input wire signed [15:0] dpd_q, input wire dpd_valid,
    input wire [31:0] threshold_error, input wire [31:0] threshold_clip,
    input wire [31:0] threshold_drift, output wire [31:0] metric_power,
    output wire [31:0] metric_error, output wire [31:0] metric_clipping,
    output wire [31:0] metric_drift, output wire metrics_valid,
    output wire retrain_request
); endmodule

(* blackbox *) module peripherals_wrapper (
    input wire clk, input wire resetn,
    input wire [11:0] uart_awaddr, input wire uart_awvalid, output wire uart_awready,
    input wire [31:0] uart_wdata, input wire [3:0] uart_wstrb, input wire uart_wvalid,
    output wire uart_wready, output wire [1:0] uart_bresp, output wire uart_bvalid,
    input wire uart_bready, input wire [11:0] uart_araddr, input wire uart_arvalid,
    output wire uart_arready, output wire [31:0] uart_rdata, output wire [1:0] uart_rresp,
    output wire uart_rvalid, input wire uart_rready, output wire uart_tx, input wire uart_rx,
    input wire [11:0] spi_awaddr, input wire spi_awvalid, output wire spi_awready,
    input wire [31:0] spi_wdata, input wire [3:0] spi_wstrb, input wire spi_wvalid,
    output wire spi_wready, output wire [1:0] spi_bresp, output wire spi_bvalid,
    input wire spi_bready, input wire [11:0] spi_araddr, input wire spi_arvalid,
    output wire spi_arready, output wire [31:0] spi_rdata, output wire [1:0] spi_rresp,
    output wire spi_rvalid, input wire spi_rready, output wire spi_sck, output wire spi_mosi,
    input wire spi_miso, output wire spi_cs, input wire irq_clear_pulse,
    input wire [31:0] irq_w1c, input wire [31:0] irq_mask, input wire capture_done,
    input wire coef_switch_done, input wire metrics_valid, input wire metric_retrain_request,
    output wire [31:0] irq_status, output wire irq, output wire retrain_request
); endmodule

(* blackbox *) module axi_ctrl_wrapper (
    input wire clk, input wire resetn,
    input wire [31:0] m_awaddr, input wire m_awvalid, output wire m_awready,
    input wire [31:0] m_wdata, input wire [3:0] m_wstrb, input wire m_wvalid,
    output wire m_wready, output wire [1:0] m_bresp, output wire m_bvalid,
    input wire m_bready, input wire [31:0] m_araddr, input wire m_arvalid,
    output wire m_arready, output wire [31:0] m_rdata, output wire [1:0] m_rresp,
    output wire m_rvalid, input wire m_rready,
    output wire [31:0] flash_araddr, output wire flash_arvalid, input wire flash_arready,
    input wire [31:0] flash_rdata, input wire [1:0] flash_rresp, input wire flash_rvalid,
    output wire flash_rready, output wire [31:0] ram_awaddr, output wire ram_awvalid,
    input wire ram_awready, output wire [31:0] ram_wdata, output wire [3:0] ram_wstrb,
    output wire ram_wvalid, input wire ram_wready, input wire [1:0] ram_bresp,
    input wire ram_bvalid, output wire ram_bready, output wire [31:0] ram_araddr,
    output wire ram_arvalid, input wire ram_arready, input wire [31:0] ram_rdata,
    input wire [1:0] ram_rresp, input wire ram_rvalid, output wire ram_rready,
    output wire [11:0] uart_awaddr, output wire uart_awvalid, input wire uart_awready,
    output wire [31:0] uart_wdata, output wire [3:0] uart_wstrb, output wire uart_wvalid,
    input wire uart_wready, input wire [1:0] uart_bresp, input wire uart_bvalid,
    output wire uart_bready, output wire [11:0] uart_araddr, output wire uart_arvalid,
    input wire uart_arready, input wire [31:0] uart_rdata, input wire [1:0] uart_rresp,
    input wire uart_rvalid, output wire uart_rready,
    output wire [11:0] spi_awaddr, output wire spi_awvalid, input wire spi_awready,
    output wire [31:0] spi_wdata, output wire [3:0] spi_wstrb, output wire spi_wvalid,
    input wire spi_wready, input wire [1:0] spi_bresp, input wire spi_bvalid,
    output wire spi_bready, output wire [11:0] spi_araddr, output wire spi_arvalid,
    input wire spi_arready, input wire [31:0] spi_rdata, input wire [1:0] spi_rresp,
    input wire spi_rvalid, output wire spi_rready,
    output wire enable, output wire force_bypass, output wire capture_start_pulse,
    output wire coef_switch_req_pulse, output wire irq_clear_pulse, output wire train_start_pulse,
    output wire [31:0] threshold_error, output wire [31:0] threshold_clip,
    output wire [31:0] threshold_drift, output wire [9:0] capture_len,
    output wire [9:0] train_sample_count, output wire [7:0] feedback_delay,
    output wire coef_we_a_pulse, output wire coef_we_b_pulse,
    output wire [6:0] coef_addr, output wire [17:0] coef_wdata,
    input wire [17:0] coef_rdata_a, input wire [17:0] coef_rdata_b,
    input wire dpd_active, input wire capture_busy, input wire capture_done,
    input wire capture_lock, input wire capture_ready, input wire train_busy,
    input wire train_done, input wire train_error, input wire coef_ready,
    input wire coef_switch_busy, input wire coef_switch_pending, input wire active_bank,
    input wire irq, input wire [31:0] irq_status, input wire [31:0] metric_power,
    input wire [31:0] metric_error, input wire [31:0] metric_clipping,
    input wire [31:0] metric_drift, input wire [31:0] mac_error_acc,
    output wire [31:0] irq_mask, output wire [31:0] irq_w1c
); endmodule

/* verilator lint_on UNDRIVEN */
/* verilator lint_on UNUSEDSIGNAL */
`endif
