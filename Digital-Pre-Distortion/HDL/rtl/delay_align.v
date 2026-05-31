// ============================================================
// delay_align.v - Feedback/reference delay alignment helper
// ============================================================
module delay_align #(
    parameter SAMPLE_WIDTH = 16,
    parameter MAX_DELAY = 256
)(
    input  wire clk,
    input  wire resetn,
    input  wire [7:0] delay_cfg,
    input  wire signed [SAMPLE_WIDTH-1:0] i_in,
    input  wire signed [SAMPLE_WIDTH-1:0] q_in,
    input  wire valid_in,
    output reg  signed [SAMPLE_WIDTH-1:0] i_out,
    output reg  signed [SAMPLE_WIDTH-1:0] q_out,
    output reg  valid_out
);
    reg signed [SAMPLE_WIDTH-1:0] i_pipe [0:MAX_DELAY-1];
    reg signed [SAMPLE_WIDTH-1:0] q_pipe [0:MAX_DELAY-1];
    reg valid_pipe [0:MAX_DELAY-1];
    integer k;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            for (k = 0; k < MAX_DELAY; k = k + 1) begin
                i_pipe[k] <= {SAMPLE_WIDTH{1'b0}};
                q_pipe[k] <= {SAMPLE_WIDTH{1'b0}};
                valid_pipe[k] <= 1'b0;
            end
            i_out <= {SAMPLE_WIDTH{1'b0}};
            q_out <= {SAMPLE_WIDTH{1'b0}};
            valid_out <= 1'b0;
        end else begin
            i_pipe[0] <= i_in;
            q_pipe[0] <= q_in;
            valid_pipe[0] <= valid_in;
            for (k = 1; k < MAX_DELAY; k = k + 1) begin
                i_pipe[k] <= i_pipe[k-1];
                q_pipe[k] <= q_pipe[k-1];
                valid_pipe[k] <= valid_pipe[k-1];
            end
            i_out <= i_pipe[delay_cfg];
            q_out <= q_pipe[delay_cfg];
            valid_out <= valid_pipe[delay_cfg];
        end
    end
endmodule
