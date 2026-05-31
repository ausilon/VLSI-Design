// ============================================================
// AXI4-Lite RAM simples - 32 bits
// Uso no projeto DPD: SRAM de trabalho para firmware/controlador.
// Sem porta de boot UART. O firmware executa a partir da SPI flash
// mapeada em 0x0000_0000 e pode usar esta RAM em 0x1000_0000.
// ============================================================
module axi_ram #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 32
)(
    input  wire                      clk,
    input  wire                      resetn,

    input  wire [31:0]               s_axi_awaddr,
    input  wire                      s_axi_awvalid,
    output reg                       s_axi_awready,

    input  wire [DATA_WIDTH-1:0]     s_axi_wdata,
    input  wire [(DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  wire                      s_axi_wvalid,
    output reg                       s_axi_wready,

    output reg  [1:0]                s_axi_bresp,
    output reg                       s_axi_bvalid,
    input  wire                      s_axi_bready,

    input  wire [31:0]               s_axi_araddr,
    input  wire                      s_axi_arvalid,
    output reg                       s_axi_arready,

    output reg  [DATA_WIDTH-1:0]     s_axi_rdata,
    output reg  [1:0]                s_axi_rresp,
    output reg                       s_axi_rvalid,
    input  wire                      s_axi_rready
);

    localparam MEM_WORDS = (1 << ADDR_WIDTH) / (DATA_WIDTH/8);

    reg [DATA_WIDTH-1:0] mem [0:MEM_WORDS-1];
    reg [31:0] awaddr_latched;
    integer i;

    always @(posedge clk) begin
        if (!resetn) begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
        end else begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;

            if (!s_axi_bvalid && !s_axi_awready && s_axi_awvalid) begin
                s_axi_awready <= 1'b1;
                awaddr_latched <= s_axi_awaddr;
            end

            if (!s_axi_bvalid && !s_axi_wready && s_axi_wvalid) begin
                s_axi_wready <= 1'b1;
                for (i = 0; i < DATA_WIDTH/8; i = i + 1) begin
                    if (s_axi_wstrb[i]) begin
                        mem[awaddr_latched[ADDR_WIDTH-1:2]][8*i +: 8] <= s_axi_wdata[8*i +: 8];
                    end
                end
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00;
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (!resetn) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= {DATA_WIDTH{1'b0}};
            s_axi_rresp   <= 2'b00;
        end else begin
            s_axi_arready <= 1'b0;

            if (!s_axi_rvalid && s_axi_arvalid) begin
                s_axi_arready <= 1'b1;
                s_axi_rdata   <= mem[s_axi_araddr[ADDR_WIDTH-1:2]];
                s_axi_rresp   <= 2'b00;
                s_axi_rvalid  <= 1'b1;
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

endmodule
