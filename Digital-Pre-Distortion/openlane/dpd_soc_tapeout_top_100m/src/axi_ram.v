// AXI4-Lite RAM used by the physical top-level integration.
// The control registers use asynchronous reset so reset is implemented on
// dedicated flop pins instead of becoming a high-fanout functional data path.
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
    reg [DATA_WIDTH-1:0] wdata_latched;
    reg [(DATA_WIDTH/8)-1:0] wstrb_latched;
    reg write_commit;
    integer i;
    wire unused_address_bits = |s_axi_araddr[31:ADDR_WIDTH]
                               | |s_axi_araddr[1:0]
                               | |awaddr_latched[31:ADDR_WIDTH]
                               | |awaddr_latched[1:0];

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            awaddr_latched <= 32'b0;
            wdata_latched <= {DATA_WIDTH{1'b0}};
            wstrb_latched <= {(DATA_WIDTH/8){1'b0}};
            write_commit  <= 1'b0;
        end else begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            write_commit  <= 1'b0;

            if (!s_axi_bvalid && !s_axi_awready && s_axi_awvalid) begin
                s_axi_awready <= 1'b1;
                awaddr_latched <= s_axi_awaddr;
            end

            if (!s_axi_bvalid && !s_axi_wready && s_axi_wvalid) begin
                s_axi_wready  <= 1'b1;
                wdata_latched <= s_axi_wdata;
                wstrb_latched <= s_axi_wstrb;
                write_commit  <= 1'b1;
                s_axi_bvalid  <= 1'b1;
                s_axi_bresp   <= 2'b00;
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    // Memory contents are intentionally not reset. write_commit is reset and
    // therefore guarantees that no write can occur while reset is asserted.
    always @(posedge clk) begin
        if (write_commit) begin
            for (i = 0; i < DATA_WIDTH/8; i = i + 1) begin
                if (wstrb_latched[i]) begin
                    mem[awaddr_latched[ADDR_WIDTH-1:2]][8*i +: 8] <=
                        wdata_latched[8*i +: 8];
                end
            end
        end
    end

    always @(posedge clk or negedge resetn) begin
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
