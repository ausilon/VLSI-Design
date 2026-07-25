// ============================================================
// metric_engine.v - Fast/monitor path metric engine
//
// Computes lightweight real-time DPD metrics from:
//   - aligned REF/FB samples: output quality proxy after PA
//   - GMP output samples: DPD output power, clipping and predistortion effort
//
// Register meaning:
//   metric_power    = EWMA L1 magnitude of GMP/DPD output
//   metric_error    = EWMA L1 error between REF and aligned FB
//   metric_clipping = saturating count of GMP-output or FB clipping events
//   metric_drift    = EWMA L1 magnitude delta between GMP output and REF
//
// This block is intentionally light: no division, no FFT and no square-root.
// EVM/ACLR-style numbers remain software/post-processing metrics for now.
// ============================================================
module metric_engine #(
    parameter SAMPLE_WIDTH = 16,
    parameter CLIP_LEVEL = 30000
)(
    input  wire clk,
    input  wire resetn,
    input  wire clear,

    input  wire signed [SAMPLE_WIDTH-1:0] ref_i,
    input  wire signed [SAMPLE_WIDTH-1:0] ref_q,
    input  wire signed [SAMPLE_WIDTH-1:0] fb_i,
    input  wire signed [SAMPLE_WIDTH-1:0] fb_q,
    input  wire sample_valid,

    input  wire signed [SAMPLE_WIDTH-1:0] dpd_i,
    input  wire signed [SAMPLE_WIDTH-1:0] dpd_q,
    input  wire dpd_valid,

    input  wire [31:0] threshold_error,
    input  wire [31:0] threshold_clip,
    input  wire [31:0] threshold_drift,

    output reg  [31:0] metric_power,
    output reg  [31:0] metric_error,
    output reg  [31:0] metric_clipping,
    output reg  [31:0] metric_drift,
    output reg         metrics_valid,
    output wire        retrain_request
);
    localparam [SAMPLE_WIDTH:0] CLIP_LEVEL_Q = CLIP_LEVEL;

    reg        s0_sample_valid;
    reg        s0_dpd_valid;
    reg        s0_clipping;
    reg [31:0] s0_dpd_mag_l1;
    reg [31:0] s0_err_mag_l1;
    reg [31:0] s0_drift_mag_l1;

    wire signed [SAMPLE_WIDTH:0] ref_i_ext = {ref_i[SAMPLE_WIDTH-1], ref_i};
    wire signed [SAMPLE_WIDTH:0] ref_q_ext = {ref_q[SAMPLE_WIDTH-1], ref_q};
    wire signed [SAMPLE_WIDTH:0] fb_i_ext = {fb_i[SAMPLE_WIDTH-1], fb_i};
    wire signed [SAMPLE_WIDTH:0] fb_q_ext = {fb_q[SAMPLE_WIDTH-1], fb_q};
    wire signed [SAMPLE_WIDTH:0] dpd_i_ext = {dpd_i[SAMPLE_WIDTH-1], dpd_i};
    wire signed [SAMPLE_WIDTH:0] dpd_q_ext = {dpd_q[SAMPLE_WIDTH-1], dpd_q};

    wire signed [SAMPLE_WIDTH:0] err_i = ref_i_ext - fb_i_ext;
    wire signed [SAMPLE_WIDTH:0] err_q = ref_q_ext - fb_q_ext;

    wire [SAMPLE_WIDTH:0] abs_ref_i = ref_i_ext[SAMPLE_WIDTH] ? -ref_i_ext : ref_i_ext;
    wire [SAMPLE_WIDTH:0] abs_ref_q = ref_q_ext[SAMPLE_WIDTH] ? -ref_q_ext : ref_q_ext;
    wire [SAMPLE_WIDTH:0] abs_fb_i = fb_i_ext[SAMPLE_WIDTH] ? -fb_i_ext : fb_i_ext;
    wire [SAMPLE_WIDTH:0] abs_fb_q = fb_q_ext[SAMPLE_WIDTH] ? -fb_q_ext : fb_q_ext;
    wire [SAMPLE_WIDTH:0] abs_dpd_i = dpd_i_ext[SAMPLE_WIDTH] ? -dpd_i_ext : dpd_i_ext;
    wire [SAMPLE_WIDTH:0] abs_dpd_q = dpd_q_ext[SAMPLE_WIDTH] ? -dpd_q_ext : dpd_q_ext;
    wire [SAMPLE_WIDTH:0] abs_err_i = err_i[SAMPLE_WIDTH] ? -err_i : err_i;
    wire [SAMPLE_WIDTH:0] abs_err_q = err_q[SAMPLE_WIDTH] ? -err_q : err_q;

    wire [31:0] ref_mag_l1 = {{(31-SAMPLE_WIDTH){1'b0}}, abs_ref_i} +
                              {{(31-SAMPLE_WIDTH){1'b0}}, abs_ref_q};
    wire [31:0] dpd_mag_l1 = {{(31-SAMPLE_WIDTH){1'b0}}, abs_dpd_i} +
                              {{(31-SAMPLE_WIDTH){1'b0}}, abs_dpd_q};
    wire [31:0] err_mag_l1 = {{(31-SAMPLE_WIDTH){1'b0}}, abs_err_i} +
                              {{(31-SAMPLE_WIDTH){1'b0}}, abs_err_q};
    wire [31:0] drift_mag_l1 = (dpd_mag_l1 >= ref_mag_l1) ?
                               (dpd_mag_l1 - ref_mag_l1) :
                               (ref_mag_l1 - dpd_mag_l1);
    wire clipping_now = (dpd_valid &&
                         ((abs_dpd_i > CLIP_LEVEL_Q) ||
                          (abs_dpd_q > CLIP_LEVEL_Q))) ||
                        (sample_valid &&
                         ((abs_fb_i > CLIP_LEVEL_Q) ||
                          (abs_fb_q > CLIP_LEVEL_Q)));

    assign retrain_request = metrics_valid &&
                             ((metric_error > threshold_error) ||
                              (metric_clipping > threshold_clip) ||
                              (metric_drift > threshold_drift));

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            metric_power    <= 32'd0;
            metric_error    <= 32'd0;
            metric_clipping <= 32'd0;
            metric_drift    <= 32'd0;
            metrics_valid   <= 1'b0;
            s0_sample_valid <= 1'b0;
            s0_dpd_valid    <= 1'b0;
            s0_clipping     <= 1'b0;
            s0_dpd_mag_l1   <= 32'd0;
            s0_err_mag_l1   <= 32'd0;
            s0_drift_mag_l1 <= 32'd0;
        end else if (clear) begin
            metric_power    <= 32'd0;
            metric_error    <= 32'd0;
            metric_clipping <= 32'd0;
            metric_drift    <= 32'd0;
            metrics_valid   <= 1'b0;
            s0_sample_valid <= 1'b0;
            s0_dpd_valid    <= 1'b0;
            s0_clipping     <= 1'b0;
            s0_dpd_mag_l1   <= 32'd0;
            s0_err_mag_l1   <= 32'd0;
            s0_drift_mag_l1 <= 32'd0;
        end else begin
            if (s0_sample_valid || s0_dpd_valid) begin
                if (s0_dpd_valid) begin
                    metric_power <= metric_power - (metric_power >> 8) + s0_dpd_mag_l1;
                    metric_drift <= metric_drift - (metric_drift >> 8) + s0_drift_mag_l1;
                end

                if (s0_sample_valid)
                    metric_error <= metric_error - (metric_error >> 8) + s0_err_mag_l1;

                if (s0_clipping && (metric_clipping != 32'hffff_ffff))
                    metric_clipping <= metric_clipping + 1'b1;

                metrics_valid <= 1'b1;
            end

            s0_sample_valid <= sample_valid;
            s0_dpd_valid    <= dpd_valid;
            s0_clipping     <= clipping_now;
            s0_dpd_mag_l1   <= dpd_mag_l1;
            s0_err_mag_l1   <= err_mag_l1;
            s0_drift_mag_l1 <= drift_mag_l1;
        end
    end
endmodule
