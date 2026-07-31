// Physical-planning coefficient-bank macro wrapper.
// Uses one 32x256 1rw1r SRAM per bank. Each 18-bit coefficient occupies one word.
module coef_bank_macro #(
    parameter COEF_WIDTH = 18,
    parameter COEF_ADDR_WIDTH = 7
)(
    input  wire clk,
    input  wire resetn,

    input  wire cpu_we_a,
    input  wire cpu_we_b,
    input  wire [COEF_ADDR_WIDTH-1:0] cpu_addr,
    input  wire [COEF_WIDTH-1:0] cpu_wdata,
    output wire [COEF_WIDTH-1:0] cpu_rdata_a,
    output wire [COEF_WIDTH-1:0] cpu_rdata_b,

    input  wire train_we_a,
    input  wire train_we_b,
    input  wire [COEF_ADDR_WIDTH-1:0] train_addr,
    input  wire [COEF_WIDTH-1:0] train_wdata,

    input  wire [COEF_ADDR_WIDTH-1:0] mac_addr,
    output wire [COEF_WIDTH-1:0] mac_rdata_a,
    output wire [COEF_WIDTH-1:0] mac_rdata_b
);
    wire wr_a = train_we_a || cpu_we_a;
    wire wr_b = train_we_b || cpu_we_b;
    wire [COEF_ADDR_WIDTH-1:0] wr_addr_a = train_we_a ? train_addr : cpu_addr;
    wire [COEF_ADDR_WIDTH-1:0] wr_addr_b = train_we_b ? train_addr : cpu_addr;
    wire [COEF_WIDTH-1:0] wr_data_a = train_we_a ? train_wdata : cpu_wdata;
    wire [COEF_WIDTH-1:0] wr_data_b = train_we_b ? train_wdata : cpu_wdata;
    wire [31:0] dout0_a;
    wire [31:0] dout1_a;
    wire [31:0] dout0_b;
    wire [31:0] dout1_b;

    assign cpu_rdata_a = dout0_a[COEF_WIDTH-1:0];
    assign cpu_rdata_b = dout0_b[COEF_WIDTH-1:0];
    assign mac_rdata_a = dout1_a[COEF_WIDTH-1:0];
    assign mac_rdata_b = dout1_b[COEF_WIDTH-1:0];

    sky130_sram_1kbyte_1rw1r_32x256_8 u_coef_bank_a (
        .clk0(clk),
        .csb0(1'b0),
        .web0(!wr_a),
        .wmask0(4'h7),
        .addr0({1'b0, wr_addr_a}),
        .din0({14'd0, wr_data_a}),
        .dout0(dout0_a),
        .clk1(clk),
        .csb1(1'b0),
        .addr1({1'b0, mac_addr}),
        .dout1(dout1_a)
    );

    sky130_sram_1kbyte_1rw1r_32x256_8 u_coef_bank_b (
        .clk0(clk),
        .csb0(1'b0),
        .web0(!wr_b),
        .wmask0(4'h7),
        .addr0({1'b0, wr_addr_b}),
        .din0({14'd0, wr_data_b}),
        .dout0(dout0_b),
        .clk1(clk),
        .csb1(1'b0),
        .addr1({1'b0, mac_addr}),
        .dout1(dout1_b)
    );
endmodule
