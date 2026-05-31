// ============================================================
// dpd_top.v - DPD subsystem integration shell
//
// Current structure aligned to DPDv1 diagram:
//   dpd_top
//   ├── axi_lite_regs
//   ├── dpd_filter
//   ├── coef_bank_a
//   ├── coef_bank_b
//   ├── coef_switch_ctrl
//   ├── capture_ram_pingpong
//   ├── delay_align
//   ├── mac_engine          (inside dpd_filter)
//   └── irq_status_ctrl
//
// CPU access remains through AXI-Lite at 0x4000_0000.
// Firmware is still expected to boot directly from SPI flash XIP.
// ============================================================
module dpd_top #(
    parameter SAMPLE_WIDTH = 16,
    parameter COEF_WIDTH   = 18,
    parameter N_COEFS      = 64,
    parameter COEF_ADDR_WIDTH = 6,
    parameter CAPTURE_ADDR_WIDTH = 10
)(
    input  wire clk,
    input  wire resetn,

    // AXI-Lite register interface from PicoRV32
    input  wire [11:0] s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output wire [1:0]  s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,

    input  wire [11:0] s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output wire [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready,

    // Baseband reference input
    input  wire signed [SAMPLE_WIDTH-1:0] sample_i_in,
    input  wire signed [SAMPLE_WIDTH-1:0] sample_q_in,
    input  wire                           sample_valid_in,
    output wire                           sample_ready_out,

    // Feedback path from PA monitor/ADC, already in baseband I/Q domain
    input  wire signed [SAMPLE_WIDTH-1:0] feedback_i_in,
    input  wire signed [SAMPLE_WIDTH-1:0] feedback_q_in,
    input  wire                           feedback_valid_in,

    // Symbol/frame boundary used for glitch-free switching
    input  wire                           sync_event,

    // Predistorted or bypassed output
    output wire signed [SAMPLE_WIDTH-1:0] sample_i_out,
    output wire signed [SAMPLE_WIDTH-1:0] sample_q_out,
    output wire                           sample_valid_out,
    input  wire                           sample_ready_in,

    output wire                           train_request,
    output wire [3:0]                     supervisor_state,
    output wire                           dpd_active,
    output wire                           irq
);

    wire enable;
    wire force_bypass;
    wire capture_start_pulse;
    wire coef_switch_req_pulse;
    wire irq_clear_pulse;
    wire [31:0] threshold_error;
    wire [31:0] threshold_clip;
    wire [31:0] threshold_drift;
    wire [CAPTURE_ADDR_WIDTH-1:0] capture_len;
    wire [7:0] feedback_delay;

    wire coef_we_a_pulse;
    wire coef_we_b_pulse;
    wire [COEF_ADDR_WIDTH-1:0] coef_cpu_addr;
    wire [COEF_WIDTH-1:0] coef_cpu_wdata;
    wire [COEF_WIDTH-1:0] coef_cpu_rdata_a;
    wire [COEF_WIDTH-1:0] coef_cpu_rdata_b;

    wire [COEF_ADDR_WIDTH-1:0] mac_coef_addr;
    wire [COEF_WIDTH-1:0] coef_data_a;
    wire [COEF_WIDTH-1:0] coef_data_b;

    wire active_bank;
    wire coef_switch_pulse;
    wire coef_switch_busy;
    wire coef_switch_pending;
    wire mac_busy;

    wire signed [SAMPLE_WIDTH-1:0] fb_i_aligned;
    wire signed [SAMPLE_WIDTH-1:0] fb_q_aligned;
    wire fb_valid_aligned;

    wire capture_busy;
    wire capture_done;
    wire capture_page;

    reg  [31:0] metric_power;
    reg  [31:0] metric_error;
    reg  [31:0] metric_clipping;
    reg  [31:0] metric_drift;
    reg         metrics_valid;

    wire [31:0] irq_status;
    wire [31:0] irq_mask;
    wire [31:0] irq_w1c;

    assign supervisor_state = {1'b0, irq, capture_busy, dpd_active};

    // --------------------------------------------------------
    // Slow path: PicoRV32 AXI-Lite register interface
    // --------------------------------------------------------
    axi_lite_regs #(
        .COEF_WIDTH(COEF_WIDTH),
        .COEF_ADDR_WIDTH(COEF_ADDR_WIDTH),
        .CAPTURE_ADDR_WIDTH(CAPTURE_ADDR_WIDTH)
    ) regs (
        .clk(clk),
        .resetn(resetn),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .enable(enable),
        .force_bypass(force_bypass),
        .capture_start_pulse(capture_start_pulse),
        .coef_switch_req_pulse(coef_switch_req_pulse),
        .irq_clear_pulse(irq_clear_pulse),
        .threshold_error(threshold_error),
        .threshold_clip(threshold_clip),
        .threshold_drift(threshold_drift),
        .capture_len(capture_len),
        .feedback_delay(feedback_delay),
        .coef_we_a_pulse(coef_we_a_pulse),
        .coef_we_b_pulse(coef_we_b_pulse),
        .coef_addr(coef_cpu_addr),
        .coef_wdata(coef_cpu_wdata),
        .coef_rdata_a(coef_cpu_rdata_a),
        .coef_rdata_b(coef_cpu_rdata_b),
        .dpd_active(dpd_active),
        .capture_busy(capture_busy),
        .capture_done(capture_done),
        .coef_switch_busy(coef_switch_busy),
        .active_bank(active_bank),
        .irq(irq),
        .irq_status(irq_status),
        .metric_power(metric_power),
        .metric_error(metric_error),
        .metric_clipping(metric_clipping),
        .metric_drift(metric_drift),
        .irq_mask(irq_mask),
        .irq_w1c(irq_w1c)
    );

    // --------------------------------------------------------
    // Coefficient memory: explicit A/B banks
    // --------------------------------------------------------
    coef_bank_a #(
        .COEF_WIDTH(COEF_WIDTH),
        .N_COEFS(N_COEFS),
        .ADDR_WIDTH(COEF_ADDR_WIDTH)
    ) bank_a (
        .clk(clk),
        .resetn(resetn),
        .cpu_we(coef_we_a_pulse),
        .cpu_addr(coef_cpu_addr),
        .cpu_wdata(coef_cpu_wdata),
        .cpu_rdata(coef_cpu_rdata_a),
        .mac_addr(mac_coef_addr),
        .mac_rdata(coef_data_a)
    );

    coef_bank_b #(
        .COEF_WIDTH(COEF_WIDTH),
        .N_COEFS(N_COEFS),
        .ADDR_WIDTH(COEF_ADDR_WIDTH)
    ) bank_b (
        .clk(clk),
        .resetn(resetn),
        .cpu_we(coef_we_b_pulse),
        .cpu_addr(coef_cpu_addr),
        .cpu_wdata(coef_cpu_wdata),
        .cpu_rdata(coef_cpu_rdata_b),
        .mac_addr(mac_coef_addr),
        .mac_rdata(coef_data_b)
    );

    coef_switch_ctrl coef_switch (
        .clk(clk),
        .resetn(resetn),
        .request_switch(coef_switch_req_pulse),
        .sync_event(sync_event),
        .datapath_idle(!mac_busy),
        .active_bank(active_bank),
        .switch_pulse(coef_switch_pulse),
        .busy(coef_switch_busy),
        .pending(coef_switch_pending)
    );

    // --------------------------------------------------------
    // Fast path: DPD filter with synchronized bypass
    // --------------------------------------------------------
    dpd_filter #(
        .SAMPLE_WIDTH(SAMPLE_WIDTH),
        .COEF_WIDTH(COEF_WIDTH),
        .N_COEFS(N_COEFS),
        .COEF_ADDR_WIDTH(COEF_ADDR_WIDTH)
    ) filter (
        .clk(clk),
        .resetn(resetn),
        .enable(enable),
        .force_bypass(force_bypass),
        .sync_event(sync_event),
        .active_bank(active_bank),
        .i_in(sample_i_in),
        .q_in(sample_q_in),
        .in_valid(sample_valid_in),
        .in_ready(sample_ready_out),
        .i_out(sample_i_out),
        .q_out(sample_q_out),
        .out_valid(sample_valid_out),
        .out_ready(sample_ready_in),
        .coef_addr(mac_coef_addr),
        .coef_data_a(coef_data_a),
        .coef_data_b(coef_data_b),
        .dpd_active(dpd_active),
        .mac_busy(mac_busy)
    );

    // --------------------------------------------------------
    // Slow/monitor path: delay alignment + ping-pong capture
    // --------------------------------------------------------
    delay_align #(
        .SAMPLE_WIDTH(SAMPLE_WIDTH),
        .MAX_DELAY(256)
    ) delay_fb (
        .clk(clk),
        .resetn(resetn),
        .delay_cfg(feedback_delay),
        .i_in(feedback_i_in),
        .q_in(feedback_q_in),
        .valid_in(feedback_valid_in),
        .i_out(fb_i_aligned),
        .q_out(fb_q_aligned),
        .valid_out(fb_valid_aligned)
    );

    capture_ram_pingpong #(
        .SAMPLE_WIDTH(SAMPLE_WIDTH),
        .ADDR_WIDTH(CAPTURE_ADDR_WIDTH)
    ) capture (
        .clk(clk),
        .resetn(resetn),
        .start(capture_start_pulse),
        .capture_len(capture_len),
        .ref_i(sample_i_in),
        .ref_q(sample_q_in),
        .fb_i(fb_i_aligned),
        .fb_q(fb_q_aligned),
        .sample_valid(sample_valid_in && fb_valid_aligned),
        .busy(capture_busy),
        .done(capture_done),
        .active_page(capture_page)
    );

    // --------------------------------------------------------
    // Minimal integer metrics. These are placeholders for the
    // later dedicated metric/MAC statistics block.
    // --------------------------------------------------------
    wire signed [SAMPLE_WIDTH:0] err_i = sample_i_in - fb_i_aligned;
    wire signed [SAMPLE_WIDTH:0] err_q = sample_q_in - fb_q_aligned;
    wire [31:0] abs_ref_i = sample_i_in[SAMPLE_WIDTH-1] ? -sample_i_in : sample_i_in;
    wire [31:0] abs_ref_q = sample_q_in[SAMPLE_WIDTH-1] ? -sample_q_in : sample_q_in;
    wire [31:0] abs_err_i = err_i[SAMPLE_WIDTH] ? -err_i : err_i;
    wire [31:0] abs_err_q = err_q[SAMPLE_WIDTH] ? -err_q : err_q;
    wire clipping_now = (abs_ref_i > 32'd30000) || (abs_ref_q > 32'd30000);

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            metric_power    <= 32'd0;
            metric_error    <= 32'd0;
            metric_clipping <= 32'd0;
            metric_drift    <= 32'd0;
            metrics_valid   <= 1'b0;
        end else if (irq_clear_pulse) begin
            metric_power    <= 32'd0;
            metric_error    <= 32'd0;
            metric_clipping <= 32'd0;
            metric_drift    <= 32'd0;
            metrics_valid   <= 1'b0;
        end else if (sample_valid_in && fb_valid_aligned) begin
            metric_power    <= metric_power - (metric_power >> 8) + abs_ref_i + abs_ref_q;
            metric_error    <= metric_error - (metric_error >> 8) + abs_err_i + abs_err_q;
            metric_clipping <= metric_clipping + clipping_now;
            metric_drift    <= (abs_err_i + abs_err_q);
            metrics_valid   <= 1'b1;
        end
    end

    irq_status_ctrl irq_ctrl (
        .clk(clk),
        .resetn(resetn),
        .clear_pulse(irq_clear_pulse),
        .w1c(irq_w1c),
        .mask(irq_mask),
        .capture_done(capture_done),
        .coef_switch_done(coef_switch_pulse),
        .metrics_valid(metrics_valid),
        .metric_error(metric_error),
        .metric_clipping(metric_clipping),
        .metric_drift(metric_drift),
        .threshold_error(threshold_error),
        .threshold_clip(threshold_clip),
        .threshold_drift(threshold_drift),
        .status(irq_status),
        .irq(irq),
        .retrain_request(train_request)
    );

endmodule
