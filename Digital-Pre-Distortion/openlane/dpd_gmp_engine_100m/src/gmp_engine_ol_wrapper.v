// ============================================================
// gmp_engine_ol_wrapper.v
//
// OpenLane timing wrapper for the DPD fast-path GMP engine.
// All external inputs are registered before the DUT and all DUT outputs are
// registered before leaving the wrapper. This makes the first 100 MHz timing
// run focus on internal registered paths instead of unconstrained IO paths.
// ============================================================
module gmp_engine_ol_wrapper #(
    parameter SAMPLE_WIDTH = 16,
    parameter COEF_WIDTH = 18,
    parameter N_COEFS = 128,
    parameter COEF_ADDR_WIDTH = 7
) (
    input  wire clk,
    input  wire resetn,

    input  wire enable_i,
    input  wire reload_coeffs_i,
    input  wire signed [SAMPLE_WIDTH-1:0] sample_i_i,
    input  wire signed [SAMPLE_WIDTH-1:0] sample_q_i,
    input  wire in_valid_i,
    input  wire out_ready_i,
    input  wire signed [COEF_WIDTH-1:0] coef_data_i,

    output reg  in_ready_o,
    output reg  signed [SAMPLE_WIDTH-1:0] sample_i_o,
    output reg  signed [SAMPLE_WIDTH-1:0] sample_q_o,
    output reg  out_valid_o,
    output reg  [COEF_ADDR_WIDTH-1:0] coef_addr_o,
    output reg  busy_o
);
    reg enable_r;
    reg reload_coeffs_r;
    reg signed [SAMPLE_WIDTH-1:0] sample_i_r;
    reg signed [SAMPLE_WIDTH-1:0] sample_q_r;
    reg in_valid_r;
    reg out_ready_r;
    reg signed [COEF_WIDTH-1:0] coef_data_r;

    wire in_ready_w;
    wire signed [SAMPLE_WIDTH-1:0] sample_i_w;
    wire signed [SAMPLE_WIDTH-1:0] sample_q_w;
    wire out_valid_w;
    wire [COEF_ADDR_WIDTH-1:0] coef_addr_w;
    wire busy_w;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            enable_r <= 1'b0;
            reload_coeffs_r <= 1'b0;
            sample_i_r <= {SAMPLE_WIDTH{1'b0}};
            sample_q_r <= {SAMPLE_WIDTH{1'b0}};
            in_valid_r <= 1'b0;
            out_ready_r <= 1'b0;
            coef_data_r <= {COEF_WIDTH{1'b0}};
            in_ready_o <= 1'b0;
            sample_i_o <= {SAMPLE_WIDTH{1'b0}};
            sample_q_o <= {SAMPLE_WIDTH{1'b0}};
            out_valid_o <= 1'b0;
            coef_addr_o <= {COEF_ADDR_WIDTH{1'b0}};
            busy_o <= 1'b0;
        end else begin
            enable_r <= enable_i;
            reload_coeffs_r <= reload_coeffs_i;
            sample_i_r <= sample_i_i;
            sample_q_r <= sample_q_i;
            in_valid_r <= in_valid_i;
            out_ready_r <= out_ready_i;
            coef_data_r <= coef_data_i;

            in_ready_o <= in_ready_w;
            sample_i_o <= sample_i_w;
            sample_q_o <= sample_q_w;
            out_valid_o <= out_valid_w;
            coef_addr_o <= coef_addr_w;
            busy_o <= busy_w;
        end
    end

    gmp_engine #(
        .SAMPLE_WIDTH(SAMPLE_WIDTH),
        .COEF_WIDTH(COEF_WIDTH),
        .N_COEFS(N_COEFS),
        .COEF_ADDR_WIDTH(COEF_ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .resetn(resetn),
        .enable(enable_r),
        .reload_coeffs(reload_coeffs_r),
        .i_in(sample_i_r),
        .q_in(sample_q_r),
        .in_valid(in_valid_r),
        .in_ready(in_ready_w),
        .i_out(sample_i_w),
        .q_out(sample_q_w),
        .out_valid(out_valid_w),
        .out_ready(out_ready_r),
        .coef_addr(coef_addr_w),
        .coef_data(coef_data_r),
        .busy(busy_w)
    );
endmodule
