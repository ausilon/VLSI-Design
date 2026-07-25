`timescale 1ns/1ps
module tb_coef_banks_manual;
  localparam W=18; localparam A=6; localparam N=64;
  reg clk, resetn, cpu_we;
  reg [A-1:0] cpu_addr, mac_addr;
  reg [W-1:0] cpu_wdata;
  wire [W-1:0] cpu_rdata_a, mac_rdata_a, cpu_rdata_b, mac_rdata_b;
  integer errors, cov_reset_zero, cov_write_a, cov_write_b, cov_cpu_read, cov_mac_read, cov_addr_low, cov_addr_mid, cov_addr_high;

  coef_bank_a #(.COEF_WIDTH(W),.N_COEFS(N),.ADDR_WIDTH(A)) dut_a(.clk(clk),.resetn(resetn),.cpu_we(cpu_we),.cpu_addr(cpu_addr),.cpu_wdata(cpu_wdata),.cpu_rdata(cpu_rdata_a),.mac_addr(mac_addr),.mac_rdata(mac_rdata_a));
  coef_bank_b #(.COEF_WIDTH(W),.N_COEFS(N),.ADDR_WIDTH(A)) dut_b(.clk(clk),.resetn(resetn),.cpu_we(cpu_we),.cpu_addr(cpu_addr),.cpu_wdata(cpu_wdata),.cpu_rdata(cpu_rdata_b),.mac_addr(mac_addr),.mac_rdata(mac_rdata_b));
  initial clk=0; always #5 clk=~clk;

  task check; input cond; input [255:0] msg; begin if(!cond) begin errors=errors+1; $display("[FAIL] %0s t=%0t",msg,$time); end else $display("[PASS] %0s",msg); end endtask
  task write_coef; input [A-1:0] addr; input [W-1:0] data; begin
    @(posedge clk); cpu_addr<=addr; cpu_wdata<=data; cpu_we<=1; @(posedge clk); cpu_we<=0; cov_write_a=cov_write_a+1; cov_write_b=cov_write_b+1;
    if (addr < 4) cov_addr_low=cov_addr_low+1; else if (addr > 59) cov_addr_high=cov_addr_high+1; else cov_addr_mid=cov_addr_mid+1;
  end endtask
  task read_check; input [A-1:0] addr; input [W-1:0] exp; begin
    @(posedge clk); cpu_addr<=addr; mac_addr<=addr; #1; cov_cpu_read=cov_cpu_read+1; cov_mac_read=cov_mac_read+1;
    check(cpu_rdata_a===exp && cpu_rdata_b===exp, "CPU read A/B matches expected");
    check(mac_rdata_a===exp && mac_rdata_b===exp, "MAC read A/B matches expected");
  end endtask
  task report_manual_coverage; begin
    $display("\n==== MANUAL COVERAGE: tb_coef_banks_manual ====");
    $display("reset_zero=%0d write_a=%0d write_b=%0d cpu_read=%0d mac_read=%0d addr_low=%0d addr_mid=%0d addr_high=%0d", cov_reset_zero,cov_write_a,cov_write_b,cov_cpu_read,cov_mac_read,cov_addr_low,cov_addr_mid,cov_addr_high);
    check(cov_reset_zero>0,"coverage: reset zero read"); check(cov_write_a>=3 && cov_write_b>=3,"coverage: writes to both banks"); check(cov_addr_low>0 && cov_addr_mid>0 && cov_addr_high>0,"coverage: low/mid/high addresses");
  end endtask
  initial begin
    errors=0; cov_reset_zero=0; cov_write_a=0; cov_write_b=0; cov_cpu_read=0; cov_mac_read=0; cov_addr_low=0; cov_addr_mid=0; cov_addr_high=0;
    resetn=0; cpu_we=0; cpu_addr=0; mac_addr=0; cpu_wdata=0; repeat(4) @(posedge clk); resetn=1; repeat(2) @(posedge clk);
    cpu_addr=0; mac_addr=0; #1; if(cpu_rdata_a===0 && cpu_rdata_b===0 && mac_rdata_a===0 && mac_rdata_b===0) cov_reset_zero=1; check(cov_reset_zero,"reset clears coefficient memories at addr 0");
    write_coef(6'd0,18'h00001); write_coef(6'd17,18'h12345); write_coef(6'd63,18'h2abcd);
    read_check(6'd0,18'h00001); read_check(6'd17,18'h12345); read_check(6'd63,18'h2abcd);
    report_manual_coverage(); if(errors==0) $display("\n[TB PASS] tb_coef_banks_manual"); else begin $display("\n[TB FAIL] errors=%0d",errors); $fatal; end $finish;
  end
endmodule
