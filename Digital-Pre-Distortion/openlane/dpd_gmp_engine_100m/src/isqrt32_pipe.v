// ============================================================
// isqrt32_pipe.v - fixed-latency unsigned integer square-root
//
// Contract:
//   - one 32-bit input may be accepted per cycle when valid_i=1
//   - one restoring-sqrt iteration per pipeline stage
//   - output is saturated to 16'h7fff to match the original GMP model
// ============================================================
module isqrt32_pipe (
    input  wire        clk,
    input  wire        resetn,
    input  wire        valid_i,
    input  wire [31:0] value_i,
    output reg         valid_o,
    output reg  [15:0] root_o
);
    localparam STAGES = 16;

    reg        valid_pipe [0:STAGES-1];
    reg [31:0] value_pipe [0:STAGES-1];
    reg [31:0] result_pipe [0:STAGES-1];

    integer s;

    function automatic [31:0] stage_bit;
        input integer idx;
        begin
            stage_bit = 32'h4000_0000 >> (2 * idx);
        end
    endfunction

    function automatic [31:0] next_value;
        input [31:0] value;
        input [31:0] result;
        input [31:0] bit_val;
        begin
            if (value >= (result + bit_val))
                next_value = value - (result + bit_val);
            else
                next_value = value;
        end
    endfunction

    function automatic [31:0] next_result;
        input [31:0] value;
        input [31:0] result;
        input [31:0] bit_val;
        begin
            if (value >= (result + bit_val))
                next_result = (result >> 1) + bit_val;
            else
                next_result = result >> 1;
        end
    endfunction

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            for (s = 0; s < STAGES; s = s + 1) begin
                valid_pipe[s] <= 1'b0;
                value_pipe[s] <= 32'd0;
                result_pipe[s] <= 32'd0;
            end
            valid_o <= 1'b0;
            root_o <= 16'd0;
        end else begin
            valid_pipe[0] <= valid_i;
            value_pipe[0] <= next_value(value_i, 32'd0, stage_bit(0));
            result_pipe[0] <= next_result(value_i, 32'd0, stage_bit(0));

            for (s = 1; s < STAGES; s = s + 1) begin
                valid_pipe[s] <= valid_pipe[s-1];
                value_pipe[s] <= next_value(value_pipe[s-1], result_pipe[s-1], stage_bit(s));
                result_pipe[s] <= next_result(value_pipe[s-1], result_pipe[s-1], stage_bit(s));
            end

            valid_o <= valid_pipe[STAGES-1];
            if (result_pipe[STAGES-1] > 32'd32767)
                root_o <= 16'h7fff;
            else
                root_o <= result_pipe[STAGES-1][15:0];
        end
    end
endmodule
