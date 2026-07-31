// Bridge from PicoRV32 native memory bus to a single-outstanding AXI4-Lite
// master. This keeps AXI-Lite internal to the SoC top-level.
module pico_native_axi_lite_bridge (
    input  wire        clk,
    input  wire        resetn,

    input  wire        mem_valid,
    input  wire [31:0] mem_addr,
    input  wire [31:0] mem_wdata,
    input  wire [3:0]  mem_wstrb,
    output reg         mem_ready,
    output reg  [31:0] mem_rdata,

    output reg  [31:0] m_awaddr,
    output reg         m_awvalid,
    input  wire        m_awready,
    output reg  [31:0] m_wdata,
    output reg  [3:0]  m_wstrb,
    output reg         m_wvalid,
    input  wire        m_wready,
    input  wire [1:0]  m_bresp,
    input  wire        m_bvalid,
    output reg         m_bready,

    output reg  [31:0] m_araddr,
    output reg         m_arvalid,
    input  wire        m_arready,
    input  wire [31:0] m_rdata,
    input  wire [1:0]  m_rresp,
    input  wire        m_rvalid,
    output reg         m_rready
);
    localparam ST_IDLE  = 3'd0;
    localparam ST_WADDR = 3'd1;
    localparam ST_WRESP = 3'd2;
    localparam ST_RADDR = 3'd3;
    localparam ST_RDATA = 3'd4;

    reg [2:0] state;
    reg aw_done;
    reg w_done;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state <= ST_IDLE;
            aw_done <= 1'b0;
            w_done <= 1'b0;
            mem_ready <= 1'b0;
            mem_rdata <= 32'd0;
            m_awaddr <= 32'd0;
            m_awvalid <= 1'b0;
            m_wdata <= 32'd0;
            m_wstrb <= 4'd0;
            m_wvalid <= 1'b0;
            m_bready <= 1'b0;
            m_araddr <= 32'd0;
            m_arvalid <= 1'b0;
            m_rready <= 1'b0;
        end else begin
            mem_ready <= 1'b0;

            case (state)
                ST_IDLE: begin
                    aw_done <= 1'b0;
                    w_done <= 1'b0;
                    m_bready <= 1'b0;
                    m_rready <= 1'b0;

                    if (mem_valid) begin
                        if (mem_wstrb != 4'd0) begin
                            m_awaddr <= mem_addr;
                            m_awvalid <= 1'b1;
                            m_wdata <= mem_wdata;
                            m_wstrb <= mem_wstrb;
                            m_wvalid <= 1'b1;
                            state <= ST_WADDR;
                        end else begin
                            m_araddr <= mem_addr;
                            m_arvalid <= 1'b1;
                            state <= ST_RADDR;
                        end
                    end
                end

                ST_WADDR: begin
                    if (m_awvalid && m_awready) begin
                        m_awvalid <= 1'b0;
                        aw_done <= 1'b1;
                    end
                    if (m_wvalid && m_wready) begin
                        m_wvalid <= 1'b0;
                        w_done <= 1'b1;
                    end
                    if ((aw_done || (m_awvalid && m_awready)) &&
                        (w_done || (m_wvalid && m_wready))) begin
                        m_bready <= 1'b1;
                        state <= ST_WRESP;
                    end
                end

                ST_WRESP: begin
                    if (m_bvalid) begin
                        m_bready <= 1'b0;
                        mem_ready <= 1'b1;
                        state <= ST_IDLE;
                    end
                end

                ST_RADDR: begin
                    if (m_arvalid && m_arready) begin
                        m_arvalid <= 1'b0;
                        m_rready <= 1'b1;
                        state <= ST_RDATA;
                    end
                end

                ST_RDATA: begin
                    if (m_rvalid) begin
                        m_rready <= 1'b0;
                        mem_rdata <= m_rdata;
                        mem_ready <= 1'b1;
                        state <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

    wire unused_resp = |m_bresp | |m_rresp;
endmodule
