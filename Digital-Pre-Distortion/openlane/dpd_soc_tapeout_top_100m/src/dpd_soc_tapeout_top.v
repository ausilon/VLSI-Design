// Connected top-level macro assembly for the DPD SoC tapeout candidate.
// AXI-Lite is internal: the PicoRV32 native memory bus is bridged to the
// AXI-Lite control fabric. External pins expose sample streams, UART/debug,
// SPI firmware memory, and status only.
module dpd_soc_tapeout_top (
    input  wire        clk,
    input  wire        fb_i_00,
    input  wire        fb_i_01,
    input  wire        fb_i_02,
    input  wire        fb_i_03,
    input  wire        fb_i_04,
    input  wire        fb_i_05,
    input  wire        fb_i_06,
    input  wire        fb_i_07,
    input  wire        fb_i_08,
    input  wire        fb_i_09,
    input  wire        fb_i_10,
    input  wire        fb_i_11,
    input  wire        fb_i_12,
    input  wire        fb_i_13,
    input  wire        fb_i_14,
    input  wire        fb_i_15,
    input  wire        fb_q_00,
    input  wire        fb_q_01,
    input  wire        fb_q_02,
    input  wire        fb_q_03,
    input  wire        fb_q_04,
    input  wire        fb_q_05,
    input  wire        fb_q_06,
    input  wire        fb_q_07,
    input  wire        fb_q_08,
    input  wire        fb_q_09,
    input  wire        fb_q_10,
    input  wire        fb_q_11,
    input  wire        fb_q_12,
    input  wire        fb_q_13,
    input  wire        fb_q_14,
    input  wire        fb_q_15,
    output wire        flash_cs,
    input  wire        flash_miso,
    output wire        flash_mosi,
    output wire        flash_sck,
    output wire        out_i_00,
    output wire        out_i_01,
    output wire        out_i_02,
    output wire        out_i_03,
    output wire        out_i_04,
    output wire        out_i_05,
    output wire        out_i_06,
    output wire        out_i_07,
    output wire        out_i_08,
    output wire        out_i_09,
    output wire        out_i_10,
    output wire        out_i_11,
    output wire        out_i_12,
    output wire        out_i_13,
    output wire        out_i_14,
    output wire        out_i_15,
    output wire        out_q_00,
    output wire        out_q_01,
    output wire        out_q_02,
    output wire        out_q_03,
    output wire        out_q_04,
    output wire        out_q_05,
    output wire        out_q_06,
    output wire        out_q_07,
    output wire        out_q_08,
    output wire        out_q_09,
    output wire        out_q_10,
    output wire        out_q_11,
    output wire        out_q_12,
    output wire        out_q_13,
    output wire        out_q_14,
    output wire        out_q_15,
    input  wire        out_ready,
    output wire        out_valid,
    input  wire        ref_i_00,
    input  wire        ref_i_01,
    input  wire        ref_i_02,
    input  wire        ref_i_03,
    input  wire        ref_i_04,
    input  wire        ref_i_05,
    input  wire        ref_i_06,
    input  wire        ref_i_07,
    input  wire        ref_i_08,
    input  wire        ref_i_09,
    input  wire        ref_i_10,
    input  wire        ref_i_11,
    input  wire        ref_i_12,
    input  wire        ref_i_13,
    input  wire        ref_i_14,
    input  wire        ref_i_15,
    input  wire        ref_q_00,
    input  wire        ref_q_01,
    input  wire        ref_q_02,
    input  wire        ref_q_03,
    input  wire        ref_q_04,
    input  wire        ref_q_05,
    input  wire        ref_q_06,
    input  wire        ref_q_07,
    input  wire        ref_q_08,
    input  wire        ref_q_09,
    input  wire        ref_q_10,
    input  wire        ref_q_11,
    input  wire        ref_q_12,
    input  wire        ref_q_13,
    input  wire        ref_q_14,
    input  wire        ref_q_15,
    input  wire        resetn,
    output wire        sample_ready,
    input  wire        sample_valid,
    input  wire        uart_rx,
    output wire        uart_tx
);
    localparam COEF_WIDTH = 18;
    localparam COEF_ADDR_WIDTH = 7;
    localparam CAPTURE_ADDR_WIDTH = 10;

    wire dbg_spi_cs;
    wire dbg_spi_miso = 1'b0;
    wire dbg_spi_mosi;
    wire dbg_spi_sck;
    wire irq;
    wire retrain_request;
    wire trap;

    wire signed [15:0] ref_i = {ref_i_15, ref_i_14, ref_i_13, ref_i_12,
                                ref_i_11, ref_i_10, ref_i_09, ref_i_08,
                                ref_i_07, ref_i_06, ref_i_05, ref_i_04,
                                ref_i_03, ref_i_02, ref_i_01, ref_i_00};
    wire signed [15:0] ref_q = {ref_q_15, ref_q_14, ref_q_13, ref_q_12,
                                ref_q_11, ref_q_10, ref_q_09, ref_q_08,
                                ref_q_07, ref_q_06, ref_q_05, ref_q_04,
                                ref_q_03, ref_q_02, ref_q_01, ref_q_00};
    wire signed [15:0] fb_i = {fb_i_15, fb_i_14, fb_i_13, fb_i_12,
                               fb_i_11, fb_i_10, fb_i_09, fb_i_08,
                               fb_i_07, fb_i_06, fb_i_05, fb_i_04,
                               fb_i_03, fb_i_02, fb_i_01, fb_i_00};
    wire signed [15:0] fb_q = {fb_q_15, fb_q_14, fb_q_13, fb_q_12,
                               fb_q_11, fb_q_10, fb_q_09, fb_q_08,
                               fb_q_07, fb_q_06, fb_q_05, fb_q_04,
                               fb_q_03, fb_q_02, fb_q_01, fb_q_00};
    wire signed [15:0] out_i;
    wire signed [15:0] out_q;
    wire signed [15:0] ref_i_stage;
    wire signed [15:0] ref_q_stage;
    wire signed [15:0] fb_i_stage;
    wire signed [15:0] fb_q_stage;
    wire               sample_valid_stage;
    reg  [1:0]         reset_sync;
    reg                uart_rx_meta;
    reg                uart_rx_sync;
    wire               core_resetn = reset_sync[1];
    wire reset_uartn;
    wire reset_inputn;
    wire reset_outputn;
    wire reset_statusn;
    wire reset_bankn;
    wire reset_picon;
    wire reset_bridgen;
    wire reset_axin;
    wire reset_flashn;
    wire reset_ramn;
    wire reset_capturen;
    wire reset_macn;
    wire reset_coefn;
    wire reset_gmpn;
    wire reset_metricsn;
    wire reset_peripheralsn;
    wire reset_controln;

    wire enable;
    wire force_bypass;
    wire capture_start_pulse;
    wire coef_switch_req_pulse;
    wire irq_clear_pulse;
    wire train_start_pulse;
    wire [31:0] threshold_error;
    wire [31:0] threshold_clip;
    wire [31:0] threshold_drift;
    wire [CAPTURE_ADDR_WIDTH-1:0] capture_len;
    wire [CAPTURE_ADDR_WIDTH-1:0] train_sample_count;
    wire [7:0] feedback_delay;
    wire coef_we_a_pulse;
    wire coef_we_b_pulse;
    wire [COEF_ADDR_WIDTH-1:0] cpu_coef_addr;
    wire [COEF_WIDTH-1:0] cpu_coef_wdata;
    wire [COEF_WIDTH-1:0] cpu_coef_rdata_a;
    wire [COEF_WIDTH-1:0] cpu_coef_rdata_b;

    wire capture_busy;
    wire capture_done;
    wire capture_lock;
    wire capture_release;
    wire capture_ready;
    wire snapshot_page;
    wire [CAPTURE_ADDR_WIDTH-1:0] mac_rd_addr;
    wire [63:0] mac_rd_data;
    wire mac_rd_en;

    wire train_busy;
    wire train_done;
    wire train_error;
    wire mac_coef_ready;
    wire mac_coef_we;
    wire [COEF_ADDR_WIDTH-1:0] mac_coef_addr;
    wire signed [COEF_WIDTH-1:0] mac_coef_wdata;
    wire [31:0] mac_error_acc;

    reg dpd_active_request_stage;
    reg dpd_active_stage;
    reg dpd_mode_pending;
    reg coef_switch_pending_reg;
    reg coef_switch_done_reg;
    reg capture_start_stage;
    reg coef_switch_req_stage;
    reg irq_clear_stage;
    reg train_start_stage;
    reg [CAPTURE_ADDR_WIDTH-1:0] capture_len_stage;
    reg [CAPTURE_ADDR_WIDTH-1:0] train_sample_count_stage;
    reg [7:0] feedback_delay_stage;
    reg coef_we_a_stage;
    reg coef_we_b_stage;
    reg [COEF_ADDR_WIDTH-1:0] cpu_coef_addr_stage;
    reg [COEF_WIDTH-1:0] cpu_coef_wdata_stage;
    reg [31:0] irq_mask_stage;
    reg [31:0] irq_w1c_stage;

    wire gmp_in_ready;
    wire signed [15:0] gmp_i;
    wire signed [15:0] gmp_q;
    wire gmp_valid;
    wire [COEF_ADDR_WIDTH-1:0] gmp_coef_addr;
    wire gmp_busy;
    wire [COEF_WIDTH-1:0] gmp_coef_rdata_a;
    wire [COEF_WIDTH-1:0] gmp_coef_rdata_b;
    wire signed [COEF_WIDTH-1:0] gmp_coef_data;

    wire [31:0] metric_power;
    wire [31:0] metric_error;
    wire [31:0] metric_clipping;
    wire [31:0] metric_drift;
    wire metrics_valid;
    wire metric_retrain_request;
    reg  [31:0] threshold_error_stage;
    reg  [31:0] threshold_clip_stage;
    reg  [31:0] threshold_drift_stage;
    reg  [31:0] metric_power_stage;
    reg  [31:0] metric_error_stage;
    reg  [31:0] metric_clipping_stage;
    reg  [31:0] metric_drift_stage;
    reg  [31:0] mac_error_acc_stage;
    reg         capture_busy_stage;
    reg         capture_done_stage;
    reg         capture_lock_stage;
    reg         capture_ready_stage;
    reg         train_busy_stage;
    reg         train_done_stage;
    reg         train_error_stage;
    reg         mac_coef_ready_stage;
    reg         metrics_valid_stage;
    reg         metric_retrain_request_stage;
    reg         irq_stage;
    reg  [31:0] irq_status_stage;
    wire periph_retrain_request;
    wire [31:0] irq_status;
    wire [31:0] irq_mask;
    wire [31:0] irq_w1c;

    wire [31:0] pico_mem_rdata;
    wire [31:0] pico_mem_addr;
    wire [31:0] pico_mem_wdata;
    wire [31:0] pico_eoi;
    wire [3:0] pico_mem_wstrb;
    wire pico_mem_ready;
    wire pico_mem_valid;
    wire pico_mem_instr;

    wire [31:0] axi_awaddr;
    wire        axi_awvalid;
    wire        axi_awready;
    wire [31:0] axi_wdata;
    wire [3:0]  axi_wstrb;
    wire        axi_wvalid;
    wire        axi_wready;
    wire [1:0]  axi_bresp;
    wire        axi_bvalid;
    wire        axi_bready;
    wire [31:0] axi_araddr;
    wire        axi_arvalid;
    wire        axi_arready;
    wire [31:0] axi_rdata;
    wire [1:0]  axi_rresp;
    wire        axi_rvalid;
    wire        axi_rready;

    wire [31:0] flash_araddr;
    wire        flash_arvalid;
    wire        flash_arready;
    wire [31:0] flash_rdata;
    wire [1:0]  flash_rresp;
    wire        flash_rvalid;
    wire        flash_rready;
    wire [1:0]  flash_bresp_unused;
    wire        flash_bvalid_unused;
    wire        flash_awready_unused;
    wire        flash_wready_unused;

    wire [31:0] ram_awaddr;
    wire        ram_awvalid;
    wire        ram_awready;
    wire [31:0] ram_wdata;
    wire [3:0]  ram_wstrb;
    wire        ram_wvalid;
    wire        ram_wready;
    wire [1:0]  ram_bresp;
    wire        ram_bvalid;
    wire        ram_bready;
    wire [31:0] ram_araddr;
    wire        ram_arvalid;
    wire        ram_arready;
    wire [31:0] ram_rdata;
    wire [1:0]  ram_rresp;
    wire        ram_rvalid;
    wire        ram_rready;

    wire [11:0] uart_awaddr;
    wire        uart_awvalid;
    wire        uart_awready;
    wire [31:0] uart_wdata;
    wire [3:0]  uart_wstrb;
    wire        uart_wvalid;
    wire        uart_wready;
    wire [1:0]  uart_bresp;
    wire        uart_bvalid;
    wire        uart_bready;
    wire [11:0] uart_araddr;
    wire        uart_arvalid;
    wire        uart_arready;
    wire [31:0] uart_rdata;
    wire [1:0]  uart_rresp;
    wire        uart_rvalid;
    wire        uart_rready;

    wire [11:0] spi_awaddr;
    wire        spi_awvalid;
    wire        spi_awready;
    wire [31:0] spi_wdata;
    wire [3:0]  spi_wstrb;
    wire        spi_wvalid;
    wire        spi_wready;
    wire [1:0]  spi_bresp;
    wire        spi_bvalid;
    wire        spi_bready;
    wire [11:0] spi_araddr;
    wire        spi_arvalid;
    wire        spi_arready;
    wire [31:0] spi_rdata;
    wire [1:0]  spi_rresp;
    wire        spi_rvalid;
    wire        spi_rready;

    reg active_bank;
    wire dpd_active = dpd_active_stage;
    wire coef_switch_busy = coef_switch_pending_reg;
    wire coef_switch_pending = coef_switch_pending_reg;
    wire coef_switch_done = coef_switch_done_reg;
    wire [63:0] input_fifo_s_data = {fb_q, fb_i, ref_q, ref_i};
    wire [63:0] input_fifo_m_data;
    wire input_fifo_s_ready;
    wire input_fifo_m_valid;
    wire input_fifo_m_ready;
    wire [31:0] output_fifo_s_data;
    wire output_fifo_s_valid;
    wire output_fifo_s_ready;
    wire [31:0] output_fifo_m_data;
    wire output_fifo_m_valid;
    wire stream_pause = dpd_mode_pending || coef_switch_pending_reg;
    wire datapath_quiescent = !input_fifo_m_valid &&
                              !output_fifo_m_valid && !gmp_valid && !gmp_busy;
    wire datapath_ready = dpd_active ? gmp_in_ready : output_fifo_s_ready;
    wire sample_fire = sample_valid_stage && datapath_ready;
    wire metric_dpd_valid = dpd_active ?
                            (gmp_valid && output_fifo_s_ready) : sample_fire;
    wire signed [15:0] metric_dpd_i = dpd_active ? gmp_i : ref_i_stage;
    wire signed [15:0] metric_dpd_q = dpd_active ? gmp_q : ref_q_stage;

    assign sample_ready = input_fifo_s_ready && !stream_pause;
    assign input_fifo_m_ready = datapath_ready;
    assign ref_i_stage = input_fifo_m_data[15:0];
    assign ref_q_stage = input_fifo_m_data[31:16];
    assign fb_i_stage  = input_fifo_m_data[47:32];
    assign fb_q_stage  = input_fifo_m_data[63:48];
    assign sample_valid_stage = input_fifo_m_valid;
    assign output_fifo_s_valid = dpd_active ? gmp_valid : sample_fire;
    assign output_fifo_s_data = dpd_active ? {gmp_q, gmp_i} :
                                             {ref_q_stage, ref_i_stage};
    assign out_i = output_fifo_m_data[15:0];
    assign out_q = output_fifo_m_data[31:16];
    assign out_valid = output_fifo_m_valid;
    assign gmp_coef_data = active_bank ? $signed(gmp_coef_rdata_b) : $signed(gmp_coef_rdata_a);
    assign retrain_request = metric_retrain_request | periph_retrain_request;
    assign out_i_00 = out_i[0];
    assign out_i_01 = out_i[1];
    assign out_i_02 = out_i[2];
    assign out_i_03 = out_i[3];
    assign out_i_04 = out_i[4];
    assign out_i_05 = out_i[5];
    assign out_i_06 = out_i[6];
    assign out_i_07 = out_i[7];
    assign out_i_08 = out_i[8];
    assign out_i_09 = out_i[9];
    assign out_i_10 = out_i[10];
    assign out_i_11 = out_i[11];
    assign out_i_12 = out_i[12];
    assign out_i_13 = out_i[13];
    assign out_i_14 = out_i[14];
    assign out_i_15 = out_i[15];
    assign out_q_00 = out_q[0];
    assign out_q_01 = out_q[1];
    assign out_q_02 = out_q[2];
    assign out_q_03 = out_q[3];
    assign out_q_04 = out_q[4];
    assign out_q_05 = out_q[5];
    assign out_q_06 = out_q[6];
    assign out_q_07 = out_q[7];
    assign out_q_08 = out_q[8];
    assign out_q_09 = out_q[9];
    assign out_q_10 = out_q[10];
    assign out_q_11 = out_q[11];
    assign out_q_12 = out_q[12];
    assign out_q_13 = out_q[13];
    assign out_q_14 = out_q[14];
    assign out_q_15 = out_q[15];

    // Asynchronous assertion and synchronous deassertion prevent reset release
    // from becoming an unconstrained chip-wide timing event.
    always @(posedge clk or negedge resetn) begin
        if (!resetn)
            reset_sync <= 2'b00;
        else
            reset_sync <= {reset_sync[0], 1'b1};
    end

    // Explicit physical branches prevent synthesis from recreating one
    // chip-wide high-fanout reset net. OpenROAD may extend each branch locally.
    (* keep = "true" *) sky130_fd_sc_hd__buf_8 u_reset_buf_uart
        (.A(core_resetn), .X(reset_uartn));
    (* keep = "true" *) sky130_fd_sc_hd__buf_8 u_reset_buf_input
        (.A(core_resetn), .X(reset_inputn));
    (* keep = "true" *) sky130_fd_sc_hd__buf_8 u_reset_buf_output
        (.A(core_resetn), .X(reset_outputn));
    (* keep = "true" *) sky130_fd_sc_hd__buf_8 u_reset_buf_status
        (.A(core_resetn), .X(reset_statusn));
    (* keep = "true" *) sky130_fd_sc_hd__buf_8 u_reset_buf_bank
        (.A(core_resetn), .X(reset_bankn));
    (* keep = "true" *) sky130_fd_sc_hd__buf_8 u_reset_buf_pico
        (.A(core_resetn), .X(reset_picon));
    (* keep = "true" *) sky130_fd_sc_hd__buf_8 u_reset_buf_bridge
        (.A(core_resetn), .X(reset_bridgen));
    (* keep = "true" *) sky130_fd_sc_hd__buf_8 u_reset_buf_axi
        (.A(core_resetn), .X(reset_axin));
    (* keep = "true" *) sky130_fd_sc_hd__buf_8 u_reset_buf_flash
        (.A(core_resetn), .X(reset_flashn));
    (* keep = "true" *) sky130_fd_sc_hd__buf_8 u_reset_buf_ram
        (.A(core_resetn), .X(reset_ramn));
    (* keep = "true" *) sky130_fd_sc_hd__buf_8 u_reset_buf_capture
        (.A(core_resetn), .X(reset_capturen));
    (* keep = "true" *) sky130_fd_sc_hd__buf_8 u_reset_buf_mac
        (.A(core_resetn), .X(reset_macn));
    (* keep = "true" *) sky130_fd_sc_hd__buf_8 u_reset_buf_coef
        (.A(core_resetn), .X(reset_coefn));
    (* keep = "true" *) sky130_fd_sc_hd__buf_8 u_reset_buf_gmp
        (.A(core_resetn), .X(reset_gmpn));
    (* keep = "true" *) sky130_fd_sc_hd__buf_8 u_reset_buf_metrics
        (.A(core_resetn), .X(reset_metricsn));
    (* keep = "true" *) sky130_fd_sc_hd__buf_8 u_reset_buf_peripherals
        (.A(core_resetn), .X(reset_peripheralsn));
    (* keep = "true" *) sky130_fd_sc_hd__buf_8 u_reset_buf_control
        (.A(core_resetn), .X(reset_controln));

    always @(posedge clk or negedge reset_uartn) begin
        if (!reset_uartn) begin
            uart_rx_meta <= 1'b1;
            uart_rx_sync <= 1'b1;
        end else begin
            uart_rx_meta <= uart_rx;
            uart_rx_sync <= uart_rx_meta;
        end
    end

    elastic_fifo2 #(.WIDTH(64)) u_input_fifo (
        .clk(clk),
        .resetn(reset_inputn),
        .s_data(input_fifo_s_data),
        .s_valid(sample_valid && !stream_pause),
        .s_ready(input_fifo_s_ready),
        .m_data(input_fifo_m_data),
        .m_valid(input_fifo_m_valid),
        .m_ready(input_fifo_m_ready)
    );

    elastic_fifo2 #(.WIDTH(32)) u_output_fifo (
        .clk(clk),
        .resetn(reset_outputn),
        .s_data(output_fifo_s_data),
        .s_valid(output_fifo_s_valid),
        .s_ready(output_fifo_s_ready),
        .m_data(output_fifo_m_data),
        .m_valid(output_fifo_m_valid),
        .m_ready(out_ready)
    );

    // Register control/configuration at the AXI macro boundary. Pulse controls
    // retain their one-cycle semantics and all datapath decisions are local.
    always @(posedge clk or negedge reset_controln) begin
        if (!reset_controln) begin
            dpd_active_request_stage <= 1'b0;
            capture_start_stage      <= 1'b0;
            coef_switch_req_stage    <= 1'b0;
            irq_clear_stage          <= 1'b0;
            train_start_stage        <= 1'b0;
            capture_len_stage        <= {CAPTURE_ADDR_WIDTH{1'b0}};
            train_sample_count_stage <= {CAPTURE_ADDR_WIDTH{1'b0}};
            feedback_delay_stage     <= 8'd0;
            coef_we_a_stage          <= 1'b0;
            coef_we_b_stage          <= 1'b0;
            cpu_coef_addr_stage      <= {COEF_ADDR_WIDTH{1'b0}};
            cpu_coef_wdata_stage     <= {COEF_WIDTH{1'b0}};
            irq_mask_stage           <= 32'd0;
            irq_w1c_stage            <= 32'd0;
        end else begin
            dpd_active_request_stage <= enable && !force_bypass;
            capture_start_stage      <= capture_start_pulse;
            coef_switch_req_stage    <= coef_switch_req_pulse;
            irq_clear_stage          <= irq_clear_pulse;
            train_start_stage        <= train_start_pulse;
            capture_len_stage        <= capture_len;
            train_sample_count_stage <= train_sample_count;
            feedback_delay_stage     <= feedback_delay;
            coef_we_a_stage          <= coef_we_a_pulse;
            coef_we_b_stage          <= coef_we_b_pulse;
            cpu_coef_addr_stage      <= cpu_coef_addr;
            cpu_coef_wdata_stage     <= cpu_coef_wdata;
            irq_mask_stage           <= irq_mask;
            irq_w1c_stage            <= irq_w1c;
        end
    end

    always @(posedge clk or negedge reset_statusn) begin
        if (!reset_statusn) begin
            threshold_error_stage  <= 32'd0;
            threshold_clip_stage   <= 32'd0;
            threshold_drift_stage  <= 32'd0;
            metric_power_stage     <= 32'd0;
            metric_error_stage     <= 32'd0;
            metric_clipping_stage  <= 32'd0;
            metric_drift_stage     <= 32'd0;
            mac_error_acc_stage    <= 32'd0;
            capture_busy_stage     <= 1'b0;
            capture_done_stage     <= 1'b0;
            capture_lock_stage     <= 1'b0;
            capture_ready_stage    <= 1'b0;
            train_busy_stage       <= 1'b0;
            train_done_stage       <= 1'b0;
            train_error_stage      <= 1'b0;
            mac_coef_ready_stage   <= 1'b0;
            metrics_valid_stage    <= 1'b0;
            metric_retrain_request_stage <= 1'b0;
            irq_stage              <= 1'b0;
            irq_status_stage       <= 32'd0;
        end else begin
            threshold_error_stage  <= threshold_error;
            threshold_clip_stage   <= threshold_clip;
            threshold_drift_stage  <= threshold_drift;
            metric_power_stage     <= metric_power;
            metric_error_stage     <= metric_error;
            metric_clipping_stage  <= metric_clipping;
            metric_drift_stage     <= metric_drift;
            mac_error_acc_stage    <= mac_error_acc;
            capture_busy_stage     <= capture_busy;
            capture_done_stage     <= capture_done;
            capture_lock_stage     <= capture_lock;
            capture_ready_stage    <= capture_ready;
            train_busy_stage       <= train_busy;
            train_done_stage       <= train_done;
            train_error_stage      <= train_error;
            mac_coef_ready_stage   <= mac_coef_ready;
            metrics_valid_stage    <= metrics_valid;
            metric_retrain_request_stage <= metric_retrain_request;
            irq_stage              <= irq;
            irq_status_stage       <= irq_status;
        end
    end

    always @(posedge clk or negedge reset_bankn) begin
        if (!reset_bankn) begin
            active_bank             <= 1'b0;
            dpd_active_stage        <= 1'b0;
            dpd_mode_pending        <= 1'b0;
            coef_switch_pending_reg <= 1'b0;
            coef_switch_done_reg    <= 1'b0;
        end else begin
            coef_switch_done_reg <= 1'b0;

            if (!dpd_mode_pending) begin
                if (dpd_active_request_stage != dpd_active_stage) begin
                    dpd_mode_pending <= 1'b1;
                end
            end else if (dpd_active_request_stage == dpd_active_stage) begin
                dpd_mode_pending <= 1'b0;
            end else begin
                if (datapath_quiescent) begin
                    dpd_active_stage <= dpd_active_request_stage;
                    dpd_mode_pending <= 1'b0;
                end
            end

            if (coef_switch_req_stage && mac_coef_ready_stage)
                coef_switch_pending_reg <= 1'b1;

            if (coef_switch_pending_reg && datapath_quiescent) begin
                active_bank             <= ~active_bank;
                coef_switch_pending_reg <= 1'b0;
                coef_switch_done_reg    <= 1'b1;
            end
        end
    end

    picorv32_ol_wrapper u_pico (
        .clk(clk),
        .resetn(reset_picon),
        .mem_ready(pico_mem_ready),
        .mem_rdata(pico_mem_rdata),
        .irq({31'd0, irq_stage}),
        .trap(trap),
        .mem_valid(pico_mem_valid),
        .mem_instr(pico_mem_instr),
        .mem_addr(pico_mem_addr),
        .mem_wdata(pico_mem_wdata),
        .mem_wstrb(pico_mem_wstrb),
        .eoi(pico_eoi)
    );

    pico_native_axi_lite_bridge u_pico_axi_bridge (
        .clk(clk),
        .resetn(reset_bridgen),
        .mem_valid(pico_mem_valid),
        .mem_addr(pico_mem_addr),
        .mem_wdata(pico_mem_wdata),
        .mem_wstrb(pico_mem_wstrb),
        .mem_ready(pico_mem_ready),
        .mem_rdata(pico_mem_rdata),
        .m_awaddr(axi_awaddr),
        .m_awvalid(axi_awvalid),
        .m_awready(axi_awready),
        .m_wdata(axi_wdata),
        .m_wstrb(axi_wstrb),
        .m_wvalid(axi_wvalid),
        .m_wready(axi_wready),
        .m_bresp(axi_bresp),
        .m_bvalid(axi_bvalid),
        .m_bready(axi_bready),
        .m_araddr(axi_araddr),
        .m_arvalid(axi_arvalid),
        .m_arready(axi_arready),
        .m_rdata(axi_rdata),
        .m_rresp(axi_rresp),
        .m_rvalid(axi_rvalid),
        .m_rready(axi_rready)
    );

    axi_ctrl_wrapper u_axi (
        .clk(clk),
        .resetn(reset_axin),
        .m_awaddr(axi_awaddr),
        .m_awvalid(axi_awvalid),
        .m_awready(axi_awready),
        .m_wdata(axi_wdata),
        .m_wstrb(axi_wstrb),
        .m_wvalid(axi_wvalid),
        .m_wready(axi_wready),
        .m_bresp(axi_bresp),
        .m_bvalid(axi_bvalid),
        .m_bready(axi_bready),
        .m_araddr(axi_araddr),
        .m_arvalid(axi_arvalid),
        .m_arready(axi_arready),
        .m_rdata(axi_rdata),
        .m_rresp(axi_rresp),
        .m_rvalid(axi_rvalid),
        .m_rready(axi_rready),
        .flash_araddr(flash_araddr),
        .flash_arvalid(flash_arvalid),
        .flash_arready(flash_arready),
        .flash_rdata(flash_rdata),
        .flash_rresp(flash_rresp),
        .flash_rvalid(flash_rvalid),
        .flash_rready(flash_rready),
        .ram_awaddr(ram_awaddr),
        .ram_awvalid(ram_awvalid),
        .ram_awready(ram_awready),
        .ram_wdata(ram_wdata),
        .ram_wstrb(ram_wstrb),
        .ram_wvalid(ram_wvalid),
        .ram_wready(ram_wready),
        .ram_bresp(ram_bresp),
        .ram_bvalid(ram_bvalid),
        .ram_bready(ram_bready),
        .ram_araddr(ram_araddr),
        .ram_arvalid(ram_arvalid),
        .ram_arready(ram_arready),
        .ram_rdata(ram_rdata),
        .ram_rresp(ram_rresp),
        .ram_rvalid(ram_rvalid),
        .ram_rready(ram_rready),
        .uart_awaddr(uart_awaddr),
        .uart_awvalid(uart_awvalid),
        .uart_awready(uart_awready),
        .uart_wdata(uart_wdata),
        .uart_wstrb(uart_wstrb),
        .uart_wvalid(uart_wvalid),
        .uart_wready(uart_wready),
        .uart_bresp(uart_bresp),
        .uart_bvalid(uart_bvalid),
        .uart_bready(uart_bready),
        .uart_araddr(uart_araddr),
        .uart_arvalid(uart_arvalid),
        .uart_arready(uart_arready),
        .uart_rdata(uart_rdata),
        .uart_rresp(uart_rresp),
        .uart_rvalid(uart_rvalid),
        .uart_rready(uart_rready),
        .spi_awaddr(spi_awaddr),
        .spi_awvalid(spi_awvalid),
        .spi_awready(spi_awready),
        .spi_wdata(spi_wdata),
        .spi_wstrb(spi_wstrb),
        .spi_wvalid(spi_wvalid),
        .spi_wready(spi_wready),
        .spi_bresp(spi_bresp),
        .spi_bvalid(spi_bvalid),
        .spi_bready(spi_bready),
        .spi_araddr(spi_araddr),
        .spi_arvalid(spi_arvalid),
        .spi_arready(spi_arready),
        .spi_rdata(spi_rdata),
        .spi_rresp(spi_rresp),
        .spi_rvalid(spi_rvalid),
        .spi_rready(spi_rready),
        .enable(enable),
        .force_bypass(force_bypass),
        .capture_start_pulse(capture_start_pulse),
        .coef_switch_req_pulse(coef_switch_req_pulse),
        .irq_clear_pulse(irq_clear_pulse),
        .train_start_pulse(train_start_pulse),
        .threshold_error(threshold_error),
        .threshold_clip(threshold_clip),
        .threshold_drift(threshold_drift),
        .capture_len(capture_len),
        .train_sample_count(train_sample_count),
        .feedback_delay(feedback_delay),
        .coef_we_a_pulse(coef_we_a_pulse),
        .coef_we_b_pulse(coef_we_b_pulse),
        .coef_addr(cpu_coef_addr),
        .coef_wdata(cpu_coef_wdata),
        .coef_rdata_a(cpu_coef_rdata_a),
        .coef_rdata_b(cpu_coef_rdata_b),
        .dpd_active(dpd_active),
        .capture_busy(capture_busy_stage),
        .capture_done(capture_done_stage),
        .capture_lock(capture_lock_stage),
        .capture_ready(capture_ready_stage),
        .train_busy(train_busy_stage),
        .train_done(train_done_stage),
        .train_error(train_error_stage),
        .coef_ready(mac_coef_ready_stage),
        .coef_switch_busy(coef_switch_busy),
        .coef_switch_pending(coef_switch_pending),
        .active_bank(active_bank),
        .irq(irq_stage),
        .irq_status(irq_status_stage),
        .metric_power(metric_power_stage),
        .metric_error(metric_error_stage),
        .metric_clipping(metric_clipping_stage),
        .metric_drift(metric_drift_stage),
        .mac_error_acc(mac_error_acc_stage),
        .irq_mask(irq_mask),
        .irq_w1c(irq_w1c)
    );

    axi_spi_flash_xip #(.CLK_DIV(4)) u_flash_xip (
        .clk(clk),
        .resetn(reset_flashn),
        .s_axi_awaddr(32'd0),
        .s_axi_awvalid(1'b0),
        .s_axi_awready(flash_awready_unused),
        .s_axi_wdata(32'd0),
        .s_axi_wstrb(4'd0),
        .s_axi_wvalid(1'b0),
        .s_axi_wready(flash_wready_unused),
        .s_axi_bresp(flash_bresp_unused),
        .s_axi_bvalid(flash_bvalid_unused),
        .s_axi_bready(1'b1),
        .s_axi_araddr(flash_araddr),
        .s_axi_arvalid(flash_arvalid),
        .s_axi_arready(flash_arready),
        .s_axi_rdata(flash_rdata),
        .s_axi_rresp(flash_rresp),
        .s_axi_rvalid(flash_rvalid),
        .s_axi_rready(flash_rready),
        .flash_sck(flash_sck),
        .flash_mosi(flash_mosi),
        .flash_miso(flash_miso),
        .flash_cs(flash_cs)
    );

    axi_ram #(.ADDR_WIDTH(10), .DATA_WIDTH(32)) u_work_ram (
        .clk(clk),
        .resetn(reset_ramn),
        .s_axi_awaddr(ram_awaddr),
        .s_axi_awvalid(ram_awvalid),
        .s_axi_awready(ram_awready),
        .s_axi_wdata(ram_wdata),
        .s_axi_wstrb(ram_wstrb),
        .s_axi_wvalid(ram_wvalid),
        .s_axi_wready(ram_wready),
        .s_axi_bresp(ram_bresp),
        .s_axi_bvalid(ram_bvalid),
        .s_axi_bready(ram_bready),
        .s_axi_araddr(ram_araddr),
        .s_axi_arvalid(ram_arvalid),
        .s_axi_arready(ram_arready),
        .s_axi_rdata(ram_rdata),
        .s_axi_rresp(ram_rresp),
        .s_axi_rvalid(ram_rvalid),
        .s_axi_rready(ram_rready)
    );

    capture_ram_macro u_capture_ram (
        .clk(clk),
        .resetn(reset_capturen),
        .start(capture_start_stage),
        .capture_len(capture_len_stage),
        .ref_i(ref_i_stage),
        .ref_q(ref_q_stage),
        .fb_i(fb_i_stage),
        .fb_q(fb_q_stage),
        .sample_valid(sample_fire),
        .snapshot_lock(capture_lock),
        .rd_addr(mac_rd_addr),
        .rd_data(mac_rd_data),
        .busy(capture_busy),
        .done(capture_done),
        .snapshot_page(snapshot_page),
        .capture_ready(capture_ready)
    );

    mac_engine u_mac (
        .clk(clk),
        .resetn(reset_macn),
        .train_start(train_start_stage),
        .capture_done(capture_done),
        .train_sample_count(train_sample_count_stage),
        .capture_lock(capture_lock),
        .capture_release(capture_release),
        .mac_rd_en(mac_rd_en),
        .mac_rd_addr(mac_rd_addr),
        .mac_rd_data(mac_rd_data),
        .train_busy(train_busy),
        .train_done(train_done),
        .train_error(train_error),
        .coef_ready(mac_coef_ready),
        .coef_we(mac_coef_we),
        .coef_addr(mac_coef_addr),
        .coef_wdata(mac_coef_wdata),
        .status_error_acc(mac_error_acc)
    );

    coef_bank_macro u_coef_bank (
        .clk(clk),
        .resetn(reset_coefn),
        .cpu_we_a(coef_we_a_stage),
        .cpu_we_b(coef_we_b_stage),
        .cpu_addr(cpu_coef_addr_stage),
        .cpu_wdata(cpu_coef_wdata_stage),
        .cpu_rdata_a(cpu_coef_rdata_a),
        .cpu_rdata_b(cpu_coef_rdata_b),
        .train_we_a(mac_coef_we && active_bank),
        .train_we_b(mac_coef_we && !active_bank),
        .train_addr(mac_coef_addr),
        .train_wdata(mac_coef_wdata),
        .mac_addr(gmp_coef_addr),
        .mac_rdata_a(gmp_coef_rdata_a),
        .mac_rdata_b(gmp_coef_rdata_b)
    );

    gmp_engine_ol_wrapper u_gmp (
        .clk(clk),
        .resetn(reset_gmpn),
        .enable_i(dpd_active),
        .reload_coeffs_i(coef_switch_done),
        .sample_i_i(ref_i_stage),
        .sample_q_i(ref_q_stage),
        .in_valid_i(sample_valid_stage && dpd_active),
        .out_ready_i(output_fifo_s_ready),
        .coef_data_i(gmp_coef_data),
        .in_ready_o(gmp_in_ready),
        .sample_i_o(gmp_i),
        .sample_q_o(gmp_q),
        .out_valid_o(gmp_valid),
        .coef_addr_o(gmp_coef_addr),
        .busy_o(gmp_busy)
    );

    metric_engine u_metrics (
        .clk(clk),
        .resetn(reset_metricsn),
        .clear(irq_clear_stage),
        .ref_i(ref_i_stage),
        .ref_q(ref_q_stage),
        .fb_i(fb_i_stage),
        .fb_q(fb_q_stage),
        .sample_valid(sample_fire),
        .dpd_i(metric_dpd_i),
        .dpd_q(metric_dpd_q),
        .dpd_valid(metric_dpd_valid),
        .threshold_error(threshold_error_stage),
        .threshold_clip(threshold_clip_stage),
        .threshold_drift(threshold_drift_stage),
        .metric_power(metric_power),
        .metric_error(metric_error),
        .metric_clipping(metric_clipping),
        .metric_drift(metric_drift),
        .metrics_valid(metrics_valid),
        .retrain_request(metric_retrain_request)
    );

    peripherals_wrapper u_peripherals (
        .clk(clk),
        .resetn(reset_peripheralsn),
        .uart_awaddr(uart_awaddr),
        .uart_awvalid(uart_awvalid),
        .uart_awready(uart_awready),
        .uart_wdata(uart_wdata),
        .uart_wstrb(uart_wstrb),
        .uart_wvalid(uart_wvalid),
        .uart_wready(uart_wready),
        .uart_bresp(uart_bresp),
        .uart_bvalid(uart_bvalid),
        .uart_bready(uart_bready),
        .uart_araddr(uart_araddr),
        .uart_arvalid(uart_arvalid),
        .uart_arready(uart_arready),
        .uart_rdata(uart_rdata),
        .uart_rresp(uart_rresp),
        .uart_rvalid(uart_rvalid),
        .uart_rready(uart_rready),
        .uart_tx(uart_tx),
        .uart_rx(uart_rx_sync),
        .spi_awaddr(spi_awaddr),
        .spi_awvalid(spi_awvalid),
        .spi_awready(spi_awready),
        .spi_wdata(spi_wdata),
        .spi_wstrb(spi_wstrb),
        .spi_wvalid(spi_wvalid),
        .spi_wready(spi_wready),
        .spi_bresp(spi_bresp),
        .spi_bvalid(spi_bvalid),
        .spi_bready(spi_bready),
        .spi_araddr(spi_araddr),
        .spi_arvalid(spi_arvalid),
        .spi_arready(spi_arready),
        .spi_rdata(spi_rdata),
        .spi_rresp(spi_rresp),
        .spi_rvalid(spi_rvalid),
        .spi_rready(spi_rready),
        .spi_sck(dbg_spi_sck),
        .spi_mosi(dbg_spi_mosi),
        .spi_miso(dbg_spi_miso),
        .spi_cs(dbg_spi_cs),
        .irq_clear_pulse(irq_clear_stage),
        .irq_w1c(irq_w1c_stage),
        .irq_mask(irq_mask_stage),
        .capture_done(capture_done_stage),
        .coef_switch_done(coef_switch_done),
        .metrics_valid(metrics_valid_stage),
        .metric_retrain_request(metric_retrain_request_stage),
        .irq_status(irq_status),
        .irq(irq),
        .retrain_request(periph_retrain_request)
    );

    wire unused_top = pico_mem_instr | |pico_eoi | capture_release |
                      snapshot_page | mac_rd_en | gmp_busy |
                      |feedback_delay_stage | |flash_bresp_unused |
                      flash_bvalid_unused | flash_awready_unused |
                      flash_wready_unused | dbg_spi_cs | dbg_spi_mosi |
                      dbg_spi_sck | retrain_request | trap;
endmodule
