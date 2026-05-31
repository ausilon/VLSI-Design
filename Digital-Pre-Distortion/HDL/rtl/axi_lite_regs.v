// ============================================================
// axi_lite_regs.v - AXI-Lite register file for DPD subsystem
//
// Base address: 0x4000_0000
//
// Register map:
//   0x000 CONTROL       [0]=enable [1]=force_bypass [2]=capture_start W1P
//                       [3]=coef_switch_req W1P [4]=clear_irq W1P
//   0x004 STATUS        [0]=dpd_active [1]=capture_busy [2]=capture_done
//                       [3]=coef_switch_busy [4]=active_bank [5]=irq
//   0x008 IRQ_STATUS    W1C
//   0x00C IRQ_MASK
//   0x010 METRIC_POWER
//   0x014 METRIC_ERROR
//   0x018 METRIC_CLIPPING
//   0x01C METRIC_DRIFT
//   0x020 THRESH_ERROR
//   0x024 THRESH_CLIP
//   0x028 THRESH_DRIFT
//   0x030 COEF_ADDR
//   0x034 COEF_WDATA
//   0x038 COEF_CTRL     [0]=write_a W1P [1]=write_b W1P
//   0x03C COEF_RDATA_A
//   0x040 COEF_RDATA_B
//   0x050 CAPTURE_CTRL  [15:0]=capture_len
//   0x054 DELAY_CTRL    [7:0]=feedback_delay
// ============================================================
module axi_lite_regs #(
    parameter COEF_WIDTH = 18,
    parameter COEF_ADDR_WIDTH = 6,
    parameter CAPTURE_ADDR_WIDTH = 10
)(
    input  wire clk,
    input  wire resetn,

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
    output reg  [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready,

    output reg         enable,
    output reg         force_bypass,
    output reg         capture_start_pulse,
    output reg         coef_switch_req_pulse,
    output reg         irq_clear_pulse,

    output reg  [31:0] threshold_error,
    output reg  [31:0] threshold_clip,
    output reg  [31:0] threshold_drift,

    output reg  [CAPTURE_ADDR_WIDTH-1:0] capture_len,
    output reg  [7:0]                    feedback_delay,

    output reg                          coef_we_a_pulse,
    output reg                          coef_we_b_pulse,
    output reg  [COEF_ADDR_WIDTH-1:0]   coef_addr,
    output reg  [COEF_WIDTH-1:0]        coef_wdata,
    input  wire [COEF_WIDTH-1:0]        coef_rdata_a,
    input  wire [COEF_WIDTH-1:0]        coef_rdata_b,

    input  wire        dpd_active,
    input  wire        capture_busy,
    input  wire        capture_done,
    input  wire        coef_switch_busy,
    input  wire        active_bank,
    input  wire        irq,
    input  wire [31:0] irq_status,
    input  wire [31:0] metric_power,
    input  wire [31:0] metric_error,
    input  wire [31:0] metric_clipping,
    input  wire [31:0] metric_drift,

    output reg  [31:0] irq_mask,
    output reg  [31:0] irq_w1c
);

    reg bvalid_reg;
    reg rvalid_reg;

    wire wr_fire = s_axi_awvalid && s_axi_wvalid && s_axi_awready && s_axi_wready;
    wire rd_fire = s_axi_arvalid && s_axi_arready;

    assign s_axi_awready = !bvalid_reg;
    assign s_axi_wready  = !bvalid_reg;
    assign s_axi_bvalid  = bvalid_reg;
    assign s_axi_bresp   = 2'b00;

    assign s_axi_arready = !rvalid_reg;
    assign s_axi_rvalid  = rvalid_reg;
    assign s_axi_rresp   = 2'b00;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            enable                <= 1'b0;
            force_bypass          <= 1'b1;
            capture_start_pulse   <= 1'b0;
            coef_switch_req_pulse <= 1'b0;
            irq_clear_pulse       <= 1'b0;
            coef_we_a_pulse       <= 1'b0;
            coef_we_b_pulse       <= 1'b0;
            threshold_error       <= 32'd1000000;
            threshold_clip        <= 32'd1;
            threshold_drift       <= 32'd1000000;
            capture_len           <= {CAPTURE_ADDR_WIDTH{1'b1}};
            feedback_delay        <= 8'd0;
            coef_addr             <= {COEF_ADDR_WIDTH{1'b0}};
            coef_wdata            <= {COEF_WIDTH{1'b0}};
            irq_mask              <= 32'h0000_0007;
            irq_w1c               <= 32'd0;
            bvalid_reg            <= 1'b0;
            rvalid_reg            <= 1'b0;
            s_axi_rdata           <= 32'd0;
        end else begin
            capture_start_pulse   <= 1'b0;
            coef_switch_req_pulse <= 1'b0;
            irq_clear_pulse       <= 1'b0;
            coef_we_a_pulse       <= 1'b0;
            coef_we_b_pulse       <= 1'b0;
            irq_w1c               <= 32'd0;

            if (wr_fire) begin
                bvalid_reg <= 1'b1;
                case (s_axi_awaddr[11:0])
                    12'h000: begin
                        enable       <= s_axi_wdata[0];
                        force_bypass <= s_axi_wdata[1];
                        if (s_axi_wdata[2]) capture_start_pulse <= 1'b1;
                        if (s_axi_wdata[3]) coef_switch_req_pulse <= 1'b1;
                        if (s_axi_wdata[4]) irq_clear_pulse <= 1'b1;
                    end
                    12'h008: irq_w1c <= s_axi_wdata;
                    12'h00c: irq_mask <= s_axi_wdata;
                    12'h020: threshold_error <= s_axi_wdata;
                    12'h024: threshold_clip  <= s_axi_wdata;
                    12'h028: threshold_drift <= s_axi_wdata;
                    12'h030: coef_addr <= s_axi_wdata[COEF_ADDR_WIDTH-1:0];
                    12'h034: coef_wdata <= s_axi_wdata[COEF_WIDTH-1:0];
                    12'h038: begin
                        if (s_axi_wdata[0]) coef_we_a_pulse <= 1'b1;
                        if (s_axi_wdata[1]) coef_we_b_pulse <= 1'b1;
                    end
                    12'h050: capture_len <= s_axi_wdata[CAPTURE_ADDR_WIDTH-1:0];
                    12'h054: feedback_delay <= s_axi_wdata[7:0];
                    default: begin end
                endcase
            end else if (bvalid_reg && s_axi_bready) begin
                bvalid_reg <= 1'b0;
            end

            if (rd_fire) begin
                rvalid_reg <= 1'b1;
                case (s_axi_araddr[11:0])
                    12'h000: s_axi_rdata <= {27'd0, irq_clear_pulse, 1'b0, 1'b0, force_bypass, enable};
                    12'h004: s_axi_rdata <= {26'd0, irq, active_bank, coef_switch_busy, capture_done, capture_busy, dpd_active};
                    12'h008: s_axi_rdata <= irq_status;
                    12'h00c: s_axi_rdata <= irq_mask;
                    12'h010: s_axi_rdata <= metric_power;
                    12'h014: s_axi_rdata <= metric_error;
                    12'h018: s_axi_rdata <= metric_clipping;
                    12'h01c: s_axi_rdata <= metric_drift;
                    12'h020: s_axi_rdata <= threshold_error;
                    12'h024: s_axi_rdata <= threshold_clip;
                    12'h028: s_axi_rdata <= threshold_drift;
                    12'h030: s_axi_rdata <= {{(32-COEF_ADDR_WIDTH){1'b0}}, coef_addr};
                    12'h034: s_axi_rdata <= {{(32-COEF_WIDTH){1'b0}}, coef_wdata};
                    12'h03c: s_axi_rdata <= {{(32-COEF_WIDTH){1'b0}}, coef_rdata_a};
                    12'h040: s_axi_rdata <= {{(32-COEF_WIDTH){1'b0}}, coef_rdata_b};
                    12'h050: s_axi_rdata <= {{(32-CAPTURE_ADDR_WIDTH){1'b0}}, capture_len};
                    12'h054: s_axi_rdata <= {24'd0, feedback_delay};
                    default: s_axi_rdata <= 32'd0;
                endcase
            end else if (rvalid_reg && s_axi_rready) begin
                rvalid_reg <= 1'b0;
            end
        end
    end

endmodule
