// ============================================================
// soc_top mínimo para projeto DPD
//
// Mantido:
//   - PicoRV32 AXI como controlador
//   - SPI flash XIP para firmware direto da flash
//   - RAM AXI para stack/dados
//   - UART AXI para debug/log
//   - SPI AXI simples para debug/controle externo
//
// Removido:
//   - boot UART / boot_manager / uart_rom_receiver
//   - GPIO
//   - I2C
//   - timer/IRQ externo
//
// Próxima etapa natural para DPD:
//   adicionar AXI-Lite para registradores do supervisor DPD,
//   GMP engine, MAC/metrics e banco de coeficientes.
// ============================================================
module soc_top (
    input  wire        clk,
    input  wire        resetn,

    output wire        trap,

    // UART debug
    output wire        uart_tx,
    input  wire        uart_rx,

    // SPI debug/control
    output wire        spi_mosi,
    input  wire        spi_miso,
    output wire        spi_sck,
    output wire        spi_cs,

    // SPI flash XIP firmware
    output wire        flash_mosi,
    input  wire        flash_miso,
    output wire        flash_sck,
    output wire        flash_cs,

    // DPD streaming sample path
    input  wire signed [15:0] dpd_i_in,
    input  wire signed [15:0] dpd_q_in,
    input  wire               dpd_sample_valid_in,
    output wire               dpd_sample_ready_out,
    input  wire signed [15:0] dpd_fb_i_in,
    input  wire signed [15:0] dpd_fb_q_in,
    input  wire               dpd_feedback_valid_in,
    input  wire               dpd_sync_event,
    output wire signed [15:0] dpd_i_out,
    output wire signed [15:0] dpd_q_out,
    output wire               dpd_sample_valid_out,
    input  wire               dpd_sample_ready_in,
    output wire               dpd_train_request,
    output wire [3:0]         dpd_supervisor_state,
    output wire               dpd_active,
    output wire               dpd_irq
);

    // AXI master vindo da CPU
    wire        mem_axi_awvalid;
    wire        mem_axi_awready;
    wire [31:0] mem_axi_awaddr;
    wire [ 2:0] mem_axi_awprot;
    wire        mem_axi_wvalid;
    wire        mem_axi_wready;
    wire [31:0] mem_axi_wdata;
    wire [ 3:0] mem_axi_wstrb;
    wire        mem_axi_bvalid;
    wire        mem_axi_bready;
    wire [1:0]  mem_axi_bresp;
    wire        mem_axi_arvalid;
    wire        mem_axi_arready;
    wire [31:0] mem_axi_araddr;
    wire [ 2:0] mem_axi_arprot;
    wire        mem_axi_rvalid;
    wire        mem_axi_rready;
    wire [31:0] mem_axi_rdata;
    wire [1:0]  mem_axi_rresp;

    // PCPI não utilizado
    wire        pcpi_valid;
    wire [31:0] pcpi_insn;
    wire [31:0] pcpi_rs1;
    wire [31:0] pcpi_rs2;
    wire [35:0] trace_data;
    wire        trace_valid;
    wire [31:0] eoi;
    wire [31:0] irq;

    assign irq = {31'd0, dpd_irq};

    picorv32_axi #(
        .PROGADDR_RESET(32'h0000_0000),
        .STACKADDR     (32'h1000_FFFC)
    ) cpu (
        .clk(clk),
        .resetn(resetn),
        .trap(trap),

        .mem_axi_awvalid(mem_axi_awvalid),
        .mem_axi_awready(mem_axi_awready),
        .mem_axi_awaddr(mem_axi_awaddr),
        .mem_axi_awprot(mem_axi_awprot),
        .mem_axi_wvalid(mem_axi_wvalid),
        .mem_axi_wready(mem_axi_wready),
        .mem_axi_wdata(mem_axi_wdata),
        .mem_axi_wstrb(mem_axi_wstrb),
        .mem_axi_bvalid(mem_axi_bvalid),
        .mem_axi_bready(mem_axi_bready),
        .mem_axi_arvalid(mem_axi_arvalid),
        .mem_axi_arready(mem_axi_arready),
        .mem_axi_araddr(mem_axi_araddr),
        .mem_axi_arprot(mem_axi_arprot),
        .mem_axi_rvalid(mem_axi_rvalid),
        .mem_axi_rready(mem_axi_rready),
        .mem_axi_rdata(mem_axi_rdata),

        .pcpi_valid(pcpi_valid),
        .pcpi_insn(pcpi_insn),
        .pcpi_rs1(pcpi_rs1),
        .pcpi_rs2(pcpi_rs2),
        .pcpi_wr(1'b0),
        .pcpi_rd(32'd0),
        .pcpi_wait(1'b0),
        .pcpi_ready(1'b0),

        .irq(irq),
        .eoi(eoi),
        .trace_valid(trace_valid),
        .trace_data(trace_data)
    );

    // FLASH XIP slave
    wire [31:0] flash_awaddr;
    wire        flash_awvalid;
    wire        flash_awready;
    wire [31:0] flash_wdata;
    wire [3:0]  flash_wstrb;
    wire        flash_wvalid;
    wire        flash_wready;
    wire [1:0]  flash_bresp;
    wire        flash_bvalid;
    wire        flash_bready;
    wire [31:0] flash_araddr;
    wire        flash_arvalid;
    wire        flash_arready;
    wire [31:0] flash_rdata;
    wire [1:0]  flash_rresp;
    wire        flash_rvalid;
    wire        flash_rready;

    // RAM slave
    wire [31:0] ram_awaddr;
    wire        ram_awvalid;
    wire        ram_awready;
    wire [31:0] ram_wdata;
    wire [3:0]  ram_wstrb;
    wire        ram_wvalid;
    wire        ram_wready;
    wire [1:0]  ram_bresp;
    wire        ram_bvalid;
    wire        ram_bready;
    wire [31:0] ram_araddr;
    wire        ram_arvalid;
    wire        ram_arready;
    wire [31:0] ram_rdata;
    wire [1:0]  ram_rresp;
    wire        ram_rvalid;
    wire        ram_rready;

    // UART slave
    wire [11:0] uart_awaddr;
    wire        uart_awvalid;
    wire        uart_awready;
    wire [31:0] uart_wdata;
    wire [3:0]  uart_wstrb;
    wire        uart_wvalid;
    wire        uart_wready;
    wire [1:0]  uart_bresp;
    wire        uart_bvalid;
    wire        uart_bready;
    wire [11:0] uart_araddr;
    wire        uart_arvalid;
    wire        uart_arready;
    wire [31:0] uart_rdata;
    wire [1:0]  uart_rresp;
    wire        uart_rvalid;
    wire        uart_rready;

    // SPI debug slave
    wire [11:0] spi_awaddr;
    wire        spi_awvalid;
    wire        spi_awready;
    wire [31:0] spi_wdata;
    wire [3:0]  spi_wstrb;
    wire        spi_wvalid;
    wire        spi_wready;
    wire [1:0]  spi_bresp;
    wire        spi_bvalid;
    wire        spi_bready;
    wire [11:0] spi_araddr;
    wire        spi_arvalid;
    wire        spi_arready;
    wire [31:0] spi_rdata;
    wire [1:0]  spi_rresp;
    wire        spi_rvalid;
    wire        spi_rready;

    // DPD control/status slave
    wire [11:0] dpd_awaddr;
    wire        dpd_awvalid;
    wire        dpd_awready;
    wire [31:0] dpd_wdata;
    wire [3:0]  dpd_wstrb;
    wire        dpd_wvalid;
    wire        dpd_wready;
    wire [1:0]  dpd_bresp;
    wire        dpd_bvalid;
    wire        dpd_bready;
    wire [11:0] dpd_araddr;
    wire        dpd_arvalid;
    wire        dpd_arready;
    wire [31:0] dpd_rdata;
    wire [1:0]  dpd_rresp;
    wire        dpd_rvalid;
    wire        dpd_rready;

    axi_interconnect interconnect (
        .clk(clk),
        .resetn(resetn),

        .m_awaddr(mem_axi_awaddr),
        .m_awvalid(mem_axi_awvalid),
        .m_awready(mem_axi_awready),
        .m_wdata(mem_axi_wdata),
        .m_wstrb(mem_axi_wstrb),
        .m_wvalid(mem_axi_wvalid),
        .m_wready(mem_axi_wready),
        .m_bresp(mem_axi_bresp),
        .m_bvalid(mem_axi_bvalid),
        .m_bready(mem_axi_bready),
        .m_araddr(mem_axi_araddr),
        .m_arvalid(mem_axi_arvalid),
        .m_arready(mem_axi_arready),
        .m_rdata(mem_axi_rdata),
        .m_rresp(mem_axi_rresp),
        .m_rvalid(mem_axi_rvalid),
        .m_rready(mem_axi_rready),

        .flash_awaddr(flash_awaddr),
        .flash_awvalid(flash_awvalid),
        .flash_awready(flash_awready),
        .flash_wdata(flash_wdata),
        .flash_wstrb(flash_wstrb),
        .flash_wvalid(flash_wvalid),
        .flash_wready(flash_wready),
        .flash_bresp(flash_bresp),
        .flash_bvalid(flash_bvalid),
        .flash_bready(flash_bready),
        .flash_araddr(flash_araddr),
        .flash_arvalid(flash_arvalid),
        .flash_arready(flash_arready),
        .flash_rdata(flash_rdata),
        .flash_rresp(flash_rresp),
        .flash_rvalid(flash_rvalid),
        .flash_rready(flash_rready),

        .ram_awaddr(ram_awaddr),
        .ram_awvalid(ram_awvalid),
        .ram_awready(ram_awready),
        .ram_wdata(ram_wdata),
        .ram_wstrb(ram_wstrb),
        .ram_wvalid(ram_wvalid),
        .ram_wready(ram_wready),
        .ram_bresp(ram_bresp),
        .ram_bvalid(ram_bvalid),
        .ram_bready(ram_bready),
        .ram_araddr(ram_araddr),
        .ram_arvalid(ram_arvalid),
        .ram_arready(ram_arready),
        .ram_rdata(ram_rdata),
        .ram_rresp(ram_rresp),
        .ram_rvalid(ram_rvalid),
        .ram_rready(ram_rready),

        .uart_awaddr(uart_awaddr),
        .uart_awvalid(uart_awvalid),
        .uart_awready(uart_awready),
        .uart_wdata(uart_wdata),
        .uart_wstrb(uart_wstrb),
        .uart_wvalid(uart_wvalid),
        .uart_wready(uart_wready),
        .uart_bresp(uart_bresp),
        .uart_bvalid(uart_bvalid),
        .uart_bready(uart_bready),
        .uart_araddr(uart_araddr),
        .uart_arvalid(uart_arvalid),
        .uart_arready(uart_arready),
        .uart_rdata(uart_rdata),
        .uart_rresp(uart_rresp),
        .uart_rvalid(uart_rvalid),
        .uart_rready(uart_rready),

        .spi_awaddr(spi_awaddr),
        .spi_awvalid(spi_awvalid),
        .spi_awready(spi_awready),
        .spi_wdata(spi_wdata),
        .spi_wstrb(spi_wstrb),
        .spi_wvalid(spi_wvalid),
        .spi_wready(spi_wready),
        .spi_bresp(spi_bresp),
        .spi_bvalid(spi_bvalid),
        .spi_bready(spi_bready),
        .spi_araddr(spi_araddr),
        .spi_arvalid(spi_arvalid),
        .spi_arready(spi_arready),
        .spi_rdata(spi_rdata),
        .spi_rresp(spi_rresp),
        .spi_rvalid(spi_rvalid),
        .spi_rready(spi_rready),

        .dpd_awaddr(dpd_awaddr),
        .dpd_awvalid(dpd_awvalid),
        .dpd_awready(dpd_awready),
        .dpd_wdata(dpd_wdata),
        .dpd_wstrb(dpd_wstrb),
        .dpd_wvalid(dpd_wvalid),
        .dpd_wready(dpd_wready),
        .dpd_bresp(dpd_bresp),
        .dpd_bvalid(dpd_bvalid),
        .dpd_bready(dpd_bready),
        .dpd_araddr(dpd_araddr),
        .dpd_arvalid(dpd_arvalid),
        .dpd_arready(dpd_arready),
        .dpd_rdata(dpd_rdata),
        .dpd_rresp(dpd_rresp),
        .dpd_rvalid(dpd_rvalid),
        .dpd_rready(dpd_rready)
    );

    axi_spi_flash_xip #(
        .CLK_DIV(4)
    ) flash_xip (
        .clk(clk),
        .resetn(resetn),
        .s_axi_awaddr(flash_awaddr),
        .s_axi_awvalid(flash_awvalid),
        .s_axi_awready(flash_awready),
        .s_axi_wdata(flash_wdata),
        .s_axi_wstrb(flash_wstrb),
        .s_axi_wvalid(flash_wvalid),
        .s_axi_wready(flash_wready),
        .s_axi_bresp(flash_bresp),
        .s_axi_bvalid(flash_bvalid),
        .s_axi_bready(flash_bready),
        .s_axi_araddr(flash_araddr),
        .s_axi_arvalid(flash_arvalid),
        .s_axi_arready(flash_arready),
        .s_axi_rdata(flash_rdata),
        .s_axi_rresp(flash_rresp),
        .s_axi_rvalid(flash_rvalid),
        .s_axi_rready(flash_rready),
        .flash_sck(flash_sck),
        .flash_mosi(flash_mosi),
        .flash_miso(flash_miso),
        .flash_cs(flash_cs)
    );

    axi_ram #(
        .ADDR_WIDTH(16),
        .DATA_WIDTH(32)
    ) ram (
        .clk(clk),
        .resetn(resetn),
        .s_axi_awaddr(ram_awaddr),
        .s_axi_awvalid(ram_awvalid),
        .s_axi_awready(ram_awready),
        .s_axi_wdata(ram_wdata),
        .s_axi_wstrb(ram_wstrb),
        .s_axi_wvalid(ram_wvalid),
        .s_axi_wready(ram_wready),
        .s_axi_bresp(ram_bresp),
        .s_axi_bvalid(ram_bvalid),
        .s_axi_bready(ram_bready),
        .s_axi_araddr(ram_araddr),
        .s_axi_arvalid(ram_arvalid),
        .s_axi_arready(ram_arready),
        .s_axi_rdata(ram_rdata),
        .s_axi_rresp(ram_rresp),
        .s_axi_rvalid(ram_rvalid),
        .s_axi_rready(ram_rready)
    );

    axi_uart uart (
        .clk(clk),
        .resetn(resetn),
        .s_axi_awaddr(uart_awaddr),
        .s_axi_awvalid(uart_awvalid),
        .s_axi_awready(uart_awready),
        .s_axi_wdata(uart_wdata),
        .s_axi_wstrb(uart_wstrb),
        .s_axi_wvalid(uart_wvalid),
        .s_axi_wready(uart_wready),
        .s_axi_bresp(uart_bresp),
        .s_axi_bvalid(uart_bvalid),
        .s_axi_bready(uart_bready),
        .s_axi_araddr(uart_araddr),
        .s_axi_arvalid(uart_arvalid),
        .s_axi_arready(uart_arready),
        .s_axi_rdata(uart_rdata),
        .s_axi_rresp(uart_rresp),
        .s_axi_rvalid(uart_rvalid),
        .s_axi_rready(uart_rready),
        .tx(uart_tx),
        .rx(uart_rx)
    );

    dpd_top dpd (
        .clk(clk),
        .resetn(resetn),
        .s_axi_awaddr(dpd_awaddr),
        .s_axi_awvalid(dpd_awvalid),
        .s_axi_awready(dpd_awready),
        .s_axi_wdata(dpd_wdata),
        .s_axi_wstrb(dpd_wstrb),
        .s_axi_wvalid(dpd_wvalid),
        .s_axi_wready(dpd_wready),
        .s_axi_bresp(dpd_bresp),
        .s_axi_bvalid(dpd_bvalid),
        .s_axi_bready(dpd_bready),
        .s_axi_araddr(dpd_araddr),
        .s_axi_arvalid(dpd_arvalid),
        .s_axi_arready(dpd_arready),
        .s_axi_rdata(dpd_rdata),
        .s_axi_rresp(dpd_rresp),
        .s_axi_rvalid(dpd_rvalid),
        .s_axi_rready(dpd_rready),
        .sample_i_in(dpd_i_in),
        .sample_q_in(dpd_q_in),
        .sample_valid_in(dpd_sample_valid_in),
        .sample_ready_out(dpd_sample_ready_out),
        .feedback_i_in(dpd_fb_i_in),
        .feedback_q_in(dpd_fb_q_in),
        .feedback_valid_in(dpd_feedback_valid_in),
        .sync_event(dpd_sync_event),
        .sample_i_out(dpd_i_out),
        .sample_q_out(dpd_q_out),
        .sample_valid_out(dpd_sample_valid_out),
        .sample_ready_in(dpd_sample_ready_in),
        .train_request(dpd_train_request),
        .supervisor_state(dpd_supervisor_state),
        .dpd_active(dpd_active),
        .irq(dpd_irq)
    );

    axi_spi spi_debug (
        .clk(clk),
        .resetn(resetn),
        .s_axi_awaddr(spi_awaddr),
        .s_axi_awvalid(spi_awvalid),
        .s_axi_awready(spi_awready),
        .s_axi_wdata(spi_wdata),
        .s_axi_wstrb(spi_wstrb),
        .s_axi_wvalid(spi_wvalid),
        .s_axi_wready(spi_wready),
        .s_axi_bresp(spi_bresp),
        .s_axi_bvalid(spi_bvalid),
        .s_axi_bready(spi_bready),
        .s_axi_araddr(spi_araddr),
        .s_axi_arvalid(spi_arvalid),
        .s_axi_arready(spi_arready),
        .s_axi_rdata(spi_rdata),
        .s_axi_rresp(spi_rresp),
        .s_axi_rvalid(spi_rvalid),
        .s_axi_rready(spi_rready),
        .spi_sck(spi_sck),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .spi_cs(spi_cs)
    );

endmodule
