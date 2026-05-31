// ============================================================
// dpd_filter.v - Fast path DPD filter wrapper
//
// Contains MAC engine and synchronized bypass selection.
// ============================================================
module dpd_filter #(
    parameter SAMPLE_WIDTH = 16,
    parameter COEF_WIDTH = 18,
    parameter N_COEFS = 64,
    parameter COEF_ADDR_WIDTH = 6
)(
    input  wire clk,
    input  wire resetn,
    input  wire enable,
    input  wire force_bypass,
    input  wire sync_event,
    input  wire active_bank,
    input  wire signed [SAMPLE_WIDTH-1:0] i_in,
    input  wire signed [SAMPLE_WIDTH-1:0] q_in,
    input  wire in_valid,
    output wire in_ready,
    output wire signed [SAMPLE_WIDTH-1:0] i_out,
    output wire signed [SAMPLE_WIDTH-1:0] q_out,
    output wire out_valid,
    input  wire out_ready,
    output wire [COEF_ADDR_WIDTH-1:0] coef_addr,
    input  wire [COEF_WIDTH-1:0] coef_data_a,
    input  wire [COEF_WIDTH-1:0] coef_data_b,
    output wire dpd_active,
    output wire mac_busy
);
    reg use_dpd;
    wire signed [SAMPLE_WIDTH-1:0] mac_i;
    wire signed [SAMPLE_WIDTH-1:0] mac_q;
    wire mac_valid;
    wire [COEF_WIDTH-1:0] active_coef_data = active_bank ? coef_data_b : coef_data_a;

    always @(posedge clk or negedge resetn) begin
        if (!resetn)
            use_dpd <= 1'b0;
        else if (sync_event)
            use_dpd <= enable && !force_bypass;
    end

    assign dpd_active = use_dpd;

    mac_engine #(
        .SAMPLE_WIDTH(SAMPLE_WIDTH),
        .COEF_WIDTH(COEF_WIDTH),
        .N_COEFS(N_COEFS),
        .COEF_ADDR_WIDTH(COEF_ADDR_WIDTH)
    ) mac (
        .clk(clk),
        .resetn(resetn),
        .enable(enable && use_dpd),
        .i_in(i_in),
        .q_in(q_in),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .i_out(mac_i),
        .q_out(mac_q),
        .out_valid(mac_valid),
        .out_ready(out_ready),
        .coef_addr(coef_addr),
        .coef_data(active_coef_data),
        .busy(mac_busy)
    );

    assign i_out = use_dpd ? mac_i : i_in;
    assign q_out = use_dpd ? mac_q : q_in;
    assign out_valid = use_dpd ? mac_valid : in_valid;
endmodule
