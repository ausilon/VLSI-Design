// ============================================================
// coef_bank_a.v - Coefficient bank A
// ============================================================
module coef_bank_a #(
    parameter COEF_WIDTH = 18,
    parameter N_COEFS = 64,
    parameter ADDR_WIDTH = 6
)(
    input  wire clk,
    input  wire resetn,
    input  wire cpu_we,
    input  wire [ADDR_WIDTH-1:0] cpu_addr,
    input  wire [COEF_WIDTH-1:0] cpu_wdata,
    output wire [COEF_WIDTH-1:0] cpu_rdata,
    input  wire [ADDR_WIDTH-1:0] mac_addr,
    output wire [COEF_WIDTH-1:0] mac_rdata
);
    reg [COEF_WIDTH-1:0] mem [0:N_COEFS-1];
    integer k;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            for (k = 0; k < N_COEFS; k = k + 1)
                mem[k] <= {COEF_WIDTH{1'b0}};
        end else if (cpu_we) begin
            mem[cpu_addr] <= cpu_wdata;
        end
    end

    assign cpu_rdata = mem[cpu_addr];
    assign mac_rdata = mem[mac_addr];
endmodule
