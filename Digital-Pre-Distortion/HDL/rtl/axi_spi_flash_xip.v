// ============================================================
// AXI4-Lite SPI Flash XIP read-only controller
//
// Objetivo: permitir que o PicoRV32 busque firmware diretamente
// de uma flash SPI serial mapeada no espaço AXI.
//
// Mapa esperado:
//   0x0000_0000 .. 0x00FF_FFFF -> SPI flash read-only
//
// Protocolo SPI usado:
//   CMD 0x03 + endereço 24 bits + leitura de 32 bits
//
// Observação: implementação simples, 1 outstanding read por vez.
// Boa para controle/supervisão DPD. Para alto desempenho, trocar por
// cache de linha ou controlador QSPI com burst/prefetch.
// ============================================================
module axi_spi_flash_xip #(
    parameter CLK_DIV = 4
)(
    input  wire        clk,
    input  wire        resetn,

    input  wire [31:0] s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,

    input  wire [31:0] s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready,

    output reg         flash_sck,
    output reg         flash_mosi,
    input  wire        flash_miso,
    output reg         flash_cs
);

    localparam ST_IDLE = 3'd0;
    localparam ST_CMD  = 3'd1;
    localparam ST_ADDR = 3'd2;
    localparam ST_READ = 3'd3;
    localparam ST_DONE = 3'd4;

    reg [2:0]  state;
    reg [7:0]  div_cnt;
    reg [5:0]  bit_cnt;
    reg [7:0]  cmd_shift;
    reg [23:0] addr_shift;
    reg [31:0] rx_shift;
    reg [31:0] araddr_latched;
    reg        active;

    wire div_tick = (div_cnt == (CLK_DIV - 1));

    assign s_axi_arready = (state == ST_IDLE) && !s_axi_rvalid;

    // Flash é read-only. Escritas recebem SLVERR, sem travar o barramento.
    assign s_axi_awready = !s_axi_bvalid;
    assign s_axi_wready  = !s_axi_bvalid;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            s_axi_bvalid <= 1'b0;
            s_axi_bresp  <= 2'b00;
        end else begin
            if (!s_axi_bvalid && s_axi_awvalid && s_axi_wvalid) begin
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b10; // SLVERR: região read-only
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state          <= ST_IDLE;
            div_cnt        <= 8'd0;
            bit_cnt        <= 6'd0;
            cmd_shift      <= 8'h03;
            addr_shift     <= 24'd0;
            rx_shift       <= 32'd0;
            araddr_latched <= 32'd0;
            flash_cs       <= 1'b1;
            flash_sck      <= 1'b0;
            flash_mosi     <= 1'b0;
            s_axi_rdata    <= 32'd0;
            s_axi_rresp    <= 2'b00;
            s_axi_rvalid   <= 1'b0;
            active         <= 1'b0;
        end else begin
            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end

            case (state)
                ST_IDLE: begin
                    flash_cs   <= 1'b1;
                    flash_sck  <= 1'b0;
                    flash_mosi <= 1'b0;
                    div_cnt    <= 8'd0;
                    active     <= 1'b0;

                    if (s_axi_arvalid && s_axi_arready) begin
                        araddr_latched <= s_axi_araddr;
                        cmd_shift      <= 8'h03;
                        addr_shift     <= s_axi_araddr[23:0];
                        rx_shift       <= 32'd0;
                        bit_cnt        <= 6'd7;
                        flash_cs       <= 1'b0;
                        flash_mosi     <= 1'b0;
                        state          <= ST_CMD;
                    end
                end

                ST_CMD: begin
                    if (div_tick) begin
                        div_cnt <= 8'd0;
                        flash_sck <= ~flash_sck;
                        if (flash_sck) begin
                            // borda de descida: prepara o próximo bit
                            cmd_shift <= {cmd_shift[6:0], 1'b0};
                            if (bit_cnt == 0) begin
                                bit_cnt    <= 6'd23;
                                flash_mosi <= addr_shift[23];
                                state      <= ST_ADDR;
                            end else begin
                                bit_cnt    <= bit_cnt - 1'b1;
                                flash_mosi <= cmd_shift[6];
                            end
                        end
                    end else begin
                        div_cnt <= div_cnt + 1'b1;
                    end
                end

                ST_ADDR: begin
                    if (div_tick) begin
                        div_cnt <= 8'd0;
                        flash_sck <= ~flash_sck;
                        if (flash_sck) begin
                            // borda de descida: prepara o próximo bit
                            addr_shift <= {addr_shift[22:0], 1'b0};
                            if (bit_cnt == 0) begin
                                bit_cnt    <= 6'd31;
                                flash_mosi <= 1'b0;
                                state      <= ST_READ;
                            end else begin
                                bit_cnt    <= bit_cnt - 1'b1;
                                flash_mosi <= addr_shift[22];
                            end
                        end
                    end else begin
                        div_cnt <= div_cnt + 1'b1;
                    end
                end

                ST_READ: begin
                    if (div_tick) begin
                        div_cnt <= 8'd0;
                        flash_sck <= ~flash_sck;
                        if (!flash_sck) begin
                            // borda de subida: amostra MISO em modo 0
                            rx_shift <= {rx_shift[30:0], flash_miso};
                            if (bit_cnt == 0) begin
                                state <= ST_DONE;
                            end else begin
                                bit_cnt <= bit_cnt - 1'b1;
                            end
                        end
                    end else begin
                        div_cnt <= div_cnt + 1'b1;
                    end
                end

                ST_DONE: begin
                    flash_cs  <= 1'b1;
                    flash_sck <= 1'b0;
                    // SPI retorna byte0, byte1, byte2, byte3.
                    // RISC-V/AXI little-endian espera byte0 nos bits [7:0].
                    s_axi_rdata  <= {rx_shift[7:0], rx_shift[15:8], rx_shift[23:16], rx_shift[31:24]};
                    s_axi_rresp  <= 2'b00;
                    s_axi_rvalid <= 1'b1;
                    state        <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
