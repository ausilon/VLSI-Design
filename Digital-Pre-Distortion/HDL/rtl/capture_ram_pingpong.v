// ============================================================
// capture_ram_pingpong.v - Ping-pong capture RAM for REF/FB pairs
//
// Captures aligned reference and feedback samples for offline/firmware
// inspection. The PicoRV32-facing read port can be added when capture
// dump over AXI is needed; this first shell keeps the capture mechanism.
// ============================================================
module capture_ram_pingpong #(
    parameter SAMPLE_WIDTH = 16,
    parameter ADDR_WIDTH = 10
)(
    input  wire clk,
    input  wire resetn,
    input  wire start,
    input  wire [ADDR_WIDTH-1:0] capture_len,
    input  wire signed [SAMPLE_WIDTH-1:0] ref_i,
    input  wire signed [SAMPLE_WIDTH-1:0] ref_q,
    input  wire signed [SAMPLE_WIDTH-1:0] fb_i,
    input  wire signed [SAMPLE_WIDTH-1:0] fb_q,
    input  wire sample_valid,
    output reg  busy,
    output reg  done,
    output reg  active_page
);
    localparam WORD_WIDTH = 4*SAMPLE_WIDTH;
    reg [WORD_WIDTH-1:0] ram0 [0:(1<<ADDR_WIDTH)-1];
    reg [WORD_WIDTH-1:0] ram1 [0:(1<<ADDR_WIDTH)-1];
    reg [ADDR_WIDTH-1:0] wr_addr;
    wire [WORD_WIDTH-1:0] packed_sample = {ref_i, ref_q, fb_i, fb_q};

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            wr_addr <= {ADDR_WIDTH{1'b0}};
            busy <= 1'b0;
            done <= 1'b0;
            active_page <= 1'b0;
        end else begin
            if (start && !busy) begin
                busy <= 1'b1;
                done <= 1'b0;
                wr_addr <= {ADDR_WIDTH{1'b0}};
                active_page <= ~active_page;
            end else if (busy && sample_valid) begin
                if (active_page)
                    ram1[wr_addr] <= packed_sample;
                else
                    ram0[wr_addr] <= packed_sample;

                if (wr_addr >= capture_len) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end else begin
                    wr_addr <= wr_addr + 1'b1;
                end
            end
        end
    end
endmodule
