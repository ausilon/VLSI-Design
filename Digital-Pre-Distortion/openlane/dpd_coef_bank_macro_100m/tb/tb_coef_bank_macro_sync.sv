`timescale 1ns/1ps
module tb_coef_bank_macro_sync;
    reg clk = 1'b0;
    reg resetn = 1'b1;
    reg cpu_we_a = 1'b0;
    reg cpu_we_b = 1'b0;
    reg [6:0] cpu_addr = 7'd0;
    reg [17:0] cpu_wdata = 18'd0;
    wire [17:0] cpu_rdata_a;
    wire [17:0] cpu_rdata_b;
    reg train_we_a = 1'b0;
    reg train_we_b = 1'b0;
    reg [6:0] train_addr = 7'd0;
    reg [17:0] train_wdata = 18'd0;
    reg [6:0] mac_addr = 7'd0;
    wire [17:0] mac_rdata_a;
    wire [17:0] mac_rdata_b;
    integer errors = 0;

    coef_bank_macro dut (.*);
    always #5 clk = ~clk;

    initial begin
        @(negedge clk);
        cpu_addr = 7'd3;
        cpu_wdata = 18'h2a155;
        cpu_we_a = 1'b1;
        @(negedge clk);
        cpu_we_a = 1'b0;
        @(posedge clk);
        #2;
        if (cpu_rdata_a !== 18'h2a155) begin
            $display("[FAIL] CPU bank A read expected=2a155 got=%h", cpu_rdata_a);
            errors = errors + 1;
        end else begin
            $display("[PASS] CPU bank A synchronous read");
        end

        @(negedge clk);
        train_addr = 7'd5;
        train_wdata = 18'h155aa;
        train_we_b = 1'b1;
        @(negedge clk);
        train_we_b = 1'b0;
        cpu_addr = 7'd5;
        mac_addr = 7'd5;
        @(posedge clk);
        #2;
        if (cpu_rdata_b !== 18'h155aa) begin
            $display("[FAIL] CPU bank B read expected=155aa got=%h", cpu_rdata_b);
            errors = errors + 1;
        end else begin
            $display("[PASS] CPU bank B synchronous read");
        end
        if (mac_rdata_b !== 18'h155aa) begin
            $display("[FAIL] GMP bank B read expected=155aa got=%h", mac_rdata_b);
            errors = errors + 1;
        end else begin
            $display("[PASS] GMP bank B synchronous read");
        end

        if (errors == 0)
            $display("[TB PASS] coefficient bank synchronous interfaces");
        else
            $fatal(1, "[TB FAIL] errors=%0d", errors);
        $finish;
    end
endmodule
