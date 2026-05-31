// ============================================================
// irq_status_ctrl.v - IRQ/status aggregation for DPD subsystem
// ============================================================
module irq_status_ctrl (
    input  wire clk,
    input  wire resetn,
    input  wire clear_pulse,
    input  wire [31:0] w1c,
    input  wire [31:0] mask,
    input  wire capture_done,
    input  wire coef_switch_done,
    input  wire metrics_valid,
    input  wire [31:0] metric_error,
    input  wire [31:0] metric_clipping,
    input  wire [31:0] metric_drift,
    input  wire [31:0] threshold_error,
    input  wire [31:0] threshold_clip,
    input  wire [31:0] threshold_drift,
    output reg  [31:0] status,
    output wire irq,
    output wire retrain_request
);
    wire metrics_bad = metrics_valid &&
                       ((metric_error > threshold_error) ||
                        (metric_clipping > threshold_clip) ||
                        (metric_drift > threshold_drift));

    assign irq = |(status & mask);
    assign retrain_request = status[2];

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            status <= 32'd0;
        end else begin
            if (clear_pulse)
                status <= 32'd0;
            else begin
                status <= status & ~w1c;
                if (capture_done)      status[0] <= 1'b1;
                if (coef_switch_done)  status[1] <= 1'b1;
                if (metrics_bad)       status[2] <= 1'b1;
            end
        end
    end
endmodule
