// ============================================================
// Interconector AXI4-Lite mínimo para controlador DPD
//
// Mapa de memória:
//   0x0000_0000 - 0x00FF_FFFF : SPI flash XIP read-only
//   0x1000_0000 - 0x1000_FFFF : RAM de trabalho
//   0x2000_0000 - 0x2000_0FFF : UART debug
//   0x3000_0000 - 0x3000_0FFF : SPI debug/control
//   0x4000_0000 - 0x4000_0FFF : DPD control/status registers
//
// Removidos: GPIO, I2C, timer e boot UART.
// ============================================================
module axi_interconnect (
    input  wire clk,
    input  wire resetn,

    input  wire [31:0] m_awaddr,
    input  wire        m_awvalid,
    output wire        m_awready,
    input  wire [31:0] m_wdata,
    input  wire [3:0]  m_wstrb,
    input  wire        m_wvalid,
    output wire        m_wready,
    output wire [1:0]  m_bresp,
    output wire        m_bvalid,
    input  wire        m_bready,

    input  wire [31:0] m_araddr,
    input  wire        m_arvalid,
    output wire        m_arready,
    output wire [31:0] m_rdata,
    output wire [1:0]  m_rresp,
    output wire        m_rvalid,
    input  wire        m_rready,

    // FLASH XIP
    output wire [31:0] flash_awaddr,
    output wire        flash_awvalid,
    input  wire        flash_awready,
    output wire [31:0] flash_wdata,
    output wire [3:0]  flash_wstrb,
    output wire        flash_wvalid,
    input  wire        flash_wready,
    input  wire [1:0]  flash_bresp,
    input  wire        flash_bvalid,
    output wire        flash_bready,
    output wire [31:0] flash_araddr,
    output wire        flash_arvalid,
    input  wire        flash_arready,
    input  wire [31:0] flash_rdata,
    input  wire [1:0]  flash_rresp,
    input  wire        flash_rvalid,
    output wire        flash_rready,

    // RAM
    output wire [31:0] ram_awaddr,
    output wire        ram_awvalid,
    input  wire        ram_awready,
    output wire [31:0] ram_wdata,
    output wire [3:0]  ram_wstrb,
    output wire        ram_wvalid,
    input  wire        ram_wready,
    input  wire [1:0]  ram_bresp,
    input  wire        ram_bvalid,
    output wire        ram_bready,
    output wire [31:0] ram_araddr,
    output wire        ram_arvalid,
    input  wire        ram_arready,
    input  wire [31:0] ram_rdata,
    input  wire [1:0]  ram_rresp,
    input  wire        ram_rvalid,
    output wire        ram_rready,

    // UART
    output wire [11:0] uart_awaddr,
    output wire        uart_awvalid,
    input  wire        uart_awready,
    output wire [31:0] uart_wdata,
    output wire [3:0]  uart_wstrb,
    output wire        uart_wvalid,
    input  wire        uart_wready,
    input  wire [1:0]  uart_bresp,
    input  wire        uart_bvalid,
    output wire        uart_bready,
    output wire [11:0] uart_araddr,
    output wire        uart_arvalid,
    input  wire        uart_arready,
    input  wire [31:0] uart_rdata,
    input  wire [1:0]  uart_rresp,
    input  wire        uart_rvalid,
    output wire        uart_rready,

    // SPI DEBUG
    output wire [11:0] spi_awaddr,
    output wire        spi_awvalid,
    input  wire        spi_awready,
    output wire [31:0] spi_wdata,
    output wire [3:0]  spi_wstrb,
    output wire        spi_wvalid,
    input  wire        spi_wready,
    input  wire [1:0]  spi_bresp,
    input  wire        spi_bvalid,
    output wire        spi_bready,
    output wire [11:0] spi_araddr,
    output wire        spi_arvalid,
    input  wire        spi_arready,
    input  wire [31:0] spi_rdata,
    input  wire [1:0]  spi_rresp,
    input  wire        spi_rvalid,
    output wire        spi_rready,

    // DPD REGISTERS
    output wire [11:0] dpd_awaddr,
    output wire        dpd_awvalid,
    input  wire        dpd_awready,
    output wire [31:0] dpd_wdata,
    output wire [3:0]  dpd_wstrb,
    output wire        dpd_wvalid,
    input  wire        dpd_wready,
    input  wire [1:0]  dpd_bresp,
    input  wire        dpd_bvalid,
    output wire        dpd_bready,
    output wire [11:0] dpd_araddr,
    output wire        dpd_arvalid,
    input  wire        dpd_arready,
    input  wire [31:0] dpd_rdata,
    input  wire [1:0]  dpd_rresp,
    input  wire        dpd_rvalid,
    output wire        dpd_rready
);

    localparam FLASH_BASE = 32'h0000_0000;
    localparam RAM_BASE   = 32'h1000_0000;
    localparam UART_BASE  = 32'h2000_0000;
    localparam SPI_BASE   = 32'h3000_0000;
    localparam DPD_BASE   = 32'h4000_0000;

    wire w_sel_flash = (m_awaddr[31:24] == FLASH_BASE[31:24]);
    wire w_sel_ram   = (m_awaddr[31:16] == RAM_BASE[31:16]);
    wire w_sel_uart  = (m_awaddr[31:12] == UART_BASE[31:12]);
    wire w_sel_spi   = (m_awaddr[31:12] == SPI_BASE[31:12]);
    wire w_sel_dpd   = (m_awaddr[31:12] == DPD_BASE[31:12]);

    wire r_sel_flash = (m_araddr[31:24] == FLASH_BASE[31:24]);
    wire r_sel_ram   = (m_araddr[31:16] == RAM_BASE[31:16]);
    wire r_sel_uart  = (m_araddr[31:12] == UART_BASE[31:12]);
    wire r_sel_spi   = (m_araddr[31:12] == SPI_BASE[31:12]);
    wire r_sel_dpd   = (m_araddr[31:12] == DPD_BASE[31:12]);

    assign flash_awvalid = m_awvalid && w_sel_flash;
    assign ram_awvalid   = m_awvalid && w_sel_ram;
    assign uart_awvalid  = m_awvalid && w_sel_uart;
    assign spi_awvalid   = m_awvalid && w_sel_spi;
    assign dpd_awvalid   = m_awvalid && w_sel_dpd;

    assign flash_awaddr = m_awaddr;
    assign ram_awaddr   = m_awaddr;
    assign uart_awaddr  = m_awaddr[11:0];
    assign spi_awaddr   = m_awaddr[11:0];
    assign dpd_awaddr   = m_awaddr[11:0];

    assign flash_wvalid = m_wvalid && w_sel_flash;
    assign ram_wvalid   = m_wvalid && w_sel_ram;
    assign uart_wvalid  = m_wvalid && w_sel_uart;
    assign spi_wvalid   = m_wvalid && w_sel_spi;
    assign dpd_wvalid   = m_wvalid && w_sel_dpd;

    assign flash_wdata = m_wdata;
    assign ram_wdata   = m_wdata;
    assign uart_wdata  = m_wdata;
    assign spi_wdata   = m_wdata;
    assign dpd_wdata   = m_wdata;

    assign flash_wstrb = m_wstrb;
    assign ram_wstrb   = m_wstrb;
    assign uart_wstrb  = m_wstrb;
    assign spi_wstrb   = m_wstrb;
    assign dpd_wstrb   = m_wstrb;

    assign m_awready = (w_sel_flash && flash_awready) |
                       (w_sel_ram   && ram_awready)   |
                       (w_sel_uart  && uart_awready)  |
                       (w_sel_spi   && spi_awready)   |
                       (w_sel_dpd   && dpd_awready);

    assign m_wready  = (w_sel_flash && flash_wready) |
                       (w_sel_ram   && ram_wready)   |
                       (w_sel_uart  && uart_wready)  |
                       (w_sel_spi   && spi_wready)   |
                       (w_sel_dpd   && dpd_wready);

    assign flash_bready = m_bready;
    assign ram_bready   = m_bready;
    assign uart_bready  = m_bready;
    assign spi_bready   = m_bready;
    assign dpd_bready   = m_bready;

    assign m_bvalid = flash_bvalid | ram_bvalid | uart_bvalid | spi_bvalid | dpd_bvalid;
    assign m_bresp  = flash_bvalid ? flash_bresp :
                      ram_bvalid   ? ram_bresp   :
                      uart_bvalid  ? uart_bresp  :
                      spi_bvalid   ? spi_bresp   :
                      dpd_bvalid   ? dpd_bresp   : 2'b00;

    assign flash_arvalid = m_arvalid && r_sel_flash;
    assign ram_arvalid   = m_arvalid && r_sel_ram;
    assign uart_arvalid  = m_arvalid && r_sel_uart;
    assign spi_arvalid   = m_arvalid && r_sel_spi;
    assign dpd_arvalid   = m_arvalid && r_sel_dpd;

    assign flash_araddr = m_araddr;
    assign ram_araddr   = m_araddr;
    assign uart_araddr  = m_araddr[11:0];
    assign spi_araddr   = m_araddr[11:0];
    assign dpd_araddr   = m_araddr[11:0];

    assign m_arready = (r_sel_flash && flash_arready) |
                       (r_sel_ram   && ram_arready)   |
                       (r_sel_uart  && uart_arready)  |
                       (r_sel_spi   && spi_arready)   |
                       (r_sel_dpd   && dpd_arready);

    assign flash_rready = m_rready;
    assign ram_rready   = m_rready;
    assign uart_rready  = m_rready;
    assign spi_rready   = m_rready;
    assign dpd_rready   = m_rready;

    assign m_rvalid = flash_rvalid | ram_rvalid | uart_rvalid | spi_rvalid | dpd_rvalid;
    assign m_rdata  = flash_rvalid ? flash_rdata :
                      ram_rvalid   ? ram_rdata   :
                      uart_rvalid  ? uart_rdata  :
                      spi_rvalid   ? spi_rdata   :
                      dpd_rvalid   ? dpd_rdata   : 32'hDEAD_BEEF;
    assign m_rresp  = flash_rvalid ? flash_rresp :
                      ram_rvalid   ? ram_rresp   :
                      uart_rvalid  ? uart_rresp  :
                      spi_rvalid   ? spi_rresp   :
                      dpd_rvalid   ? dpd_rresp   : 2'b00;

endmodule
