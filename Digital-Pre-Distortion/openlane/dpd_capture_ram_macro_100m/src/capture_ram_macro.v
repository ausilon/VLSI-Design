// Physical-planning capture RAM macro wrapper.
// Uses eight 32x512 1rw1r SRAM macros: two pages, 64-bit samples, 1024 words.
module capture_ram_macro #(
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
    input  wire snapshot_lock,
    input  wire [ADDR_WIDTH-1:0] rd_addr,
    output wire [4*SAMPLE_WIDTH-1:0] rd_data,
    output reg  busy,
    output reg  done,
    output reg  snapshot_page,
    output wire capture_ready
);
    localparam WORD_WIDTH = 4*SAMPLE_WIDTH;

    reg [ADDR_WIDTH-1:0] wr_addr;
    reg wr_page;
    wire wr_upper = wr_addr[ADDR_WIDTH-1];
    wire rd_upper = rd_addr[ADDR_WIDTH-1];
    wire [8:0] wr_addr9 = wr_addr[8:0];
    wire [8:0] rd_addr9 = rd_addr[8:0];
    wire [WORD_WIDTH-1:0] packed_sample = {ref_i, ref_q, fb_i, fb_q};

    wire [31:0] p0_l0_dout1;
    wire [31:0] p0_h0_dout1;
    wire [31:0] p0_l1_dout1;
    wire [31:0] p0_h1_dout1;
    wire [31:0] p1_l0_dout1;
    wire [31:0] p1_h0_dout1;
    wire [31:0] p1_l1_dout1;
    wire [31:0] p1_h1_dout1;

    wire write_fire = busy && sample_valid;
    wire wr_p0 = write_fire && !wr_page;
    wire wr_p1 = write_fire && wr_page;

    assign capture_ready = !busy && !snapshot_lock;
    assign rd_data = snapshot_page ?
                     (rd_upper ? {p1_h1_dout1, p1_l1_dout1} : {p1_h0_dout1, p1_l0_dout1}) :
                     (rd_upper ? {p0_h1_dout1, p0_l1_dout1} : {p0_h0_dout1, p0_l0_dout1});

    sky130_sram_2kbyte_1rw1r_32x512_8 u_page0_low0 (
        .clk0(clk), .csb0(!(wr_p0 && !wr_upper)), .web0(1'b0), .wmask0(4'hf),
        .addr0(wr_addr9), .din0(packed_sample[31:0]), .dout0(),
        .clk1(clk), .csb1(snapshot_page || rd_upper), .addr1(rd_addr9), .dout1(p0_l0_dout1)
    );
    sky130_sram_2kbyte_1rw1r_32x512_8 u_page0_high0 (
        .clk0(clk), .csb0(!(wr_p0 && !wr_upper)), .web0(1'b0), .wmask0(4'hf),
        .addr0(wr_addr9), .din0(packed_sample[63:32]), .dout0(),
        .clk1(clk), .csb1(snapshot_page || rd_upper), .addr1(rd_addr9), .dout1(p0_h0_dout1)
    );
    sky130_sram_2kbyte_1rw1r_32x512_8 u_page0_low1 (
        .clk0(clk), .csb0(!(wr_p0 && wr_upper)), .web0(1'b0), .wmask0(4'hf),
        .addr0(wr_addr9), .din0(packed_sample[31:0]), .dout0(),
        .clk1(clk), .csb1(snapshot_page || !rd_upper), .addr1(rd_addr9), .dout1(p0_l1_dout1)
    );
    sky130_sram_2kbyte_1rw1r_32x512_8 u_page0_high1 (
        .clk0(clk), .csb0(!(wr_p0 && wr_upper)), .web0(1'b0), .wmask0(4'hf),
        .addr0(wr_addr9), .din0(packed_sample[63:32]), .dout0(),
        .clk1(clk), .csb1(snapshot_page || !rd_upper), .addr1(rd_addr9), .dout1(p0_h1_dout1)
    );
    sky130_sram_2kbyte_1rw1r_32x512_8 u_page1_low0 (
        .clk0(clk), .csb0(!(wr_p1 && !wr_upper)), .web0(1'b0), .wmask0(4'hf),
        .addr0(wr_addr9), .din0(packed_sample[31:0]), .dout0(),
        .clk1(clk), .csb1(!snapshot_page || rd_upper), .addr1(rd_addr9), .dout1(p1_l0_dout1)
    );
    sky130_sram_2kbyte_1rw1r_32x512_8 u_page1_high0 (
        .clk0(clk), .csb0(!(wr_p1 && !wr_upper)), .web0(1'b0), .wmask0(4'hf),
        .addr0(wr_addr9), .din0(packed_sample[63:32]), .dout0(),
        .clk1(clk), .csb1(!snapshot_page || rd_upper), .addr1(rd_addr9), .dout1(p1_h0_dout1)
    );
    sky130_sram_2kbyte_1rw1r_32x512_8 u_page1_low1 (
        .clk0(clk), .csb0(!(wr_p1 && wr_upper)), .web0(1'b0), .wmask0(4'hf),
        .addr0(wr_addr9), .din0(packed_sample[31:0]), .dout0(),
        .clk1(clk), .csb1(!snapshot_page || !rd_upper), .addr1(rd_addr9), .dout1(p1_l1_dout1)
    );
    sky130_sram_2kbyte_1rw1r_32x512_8 u_page1_high1 (
        .clk0(clk), .csb0(!(wr_p1 && wr_upper)), .web0(1'b0), .wmask0(4'hf),
        .addr0(wr_addr9), .din0(packed_sample[63:32]), .dout0(),
        .clk1(clk), .csb1(!snapshot_page || !rd_upper), .addr1(rd_addr9), .dout1(p1_h1_dout1)
    );

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            wr_addr <= {ADDR_WIDTH{1'b0}};
            wr_page <= 1'b0;
            busy <= 1'b0;
            done <= 1'b0;
            snapshot_page <= 1'b0;
        end else begin
            if (start && capture_ready) begin
                busy <= 1'b1;
                done <= 1'b0;
                wr_addr <= {ADDR_WIDTH{1'b0}};
                wr_page <= ~snapshot_page;
            end else if (write_fire) begin
                if (wr_addr >= capture_len) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    snapshot_page <= wr_page;
                end else begin
                    wr_addr <= wr_addr + 1'b1;
                end
            end
        end
    end
endmodule
