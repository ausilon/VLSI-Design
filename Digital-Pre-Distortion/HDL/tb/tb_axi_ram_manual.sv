`timescale 1ns/1ps
module tb_axi_ram_manual;
  reg clk, resetn; reg [31:0] awaddr, wdata, araddr; reg [3:0] wstrb; reg awvalid,wvalid,bready,arvalid,rready;
  wire awready,wready,bvalid,arready,rvalid; wire [1:0] bresp,rresp; wire [31:0] rdata;
  integer errors, cov_write_full, cov_write_byte, cov_read, cov_bvalid, cov_rvalid, cov_addr0, cov_addr4;
  axi_ram #(.DATA_WIDTH(32),.ADDR_WIDTH(10)) dut(.clk(clk),.resetn(resetn),.s_axi_awaddr(awaddr),.s_axi_awvalid(awvalid),.s_axi_awready(awready),.s_axi_wdata(wdata),.s_axi_wstrb(wstrb),.s_axi_wvalid(wvalid),.s_axi_wready(wready),.s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),.s_axi_araddr(araddr),.s_axi_arvalid(arvalid),.s_axi_arready(arready),.s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rvalid(rvalid),.s_axi_rready(rready));
  initial clk=0; always #5 clk=~clk;
  task check; input cond; input [255:0] msg; begin if(!cond) begin errors=errors+1; $display("[FAIL] %0s t=%0t rdata=%h",msg,$time,rdata); end else $display("[PASS] %0s",msg); end endtask
  always @(posedge clk) if(resetn) begin if(bvalid) cov_bvalid<=cov_bvalid+1; if(rvalid) cov_rvalid<=cov_rvalid+1; end
  task axi_write; input [31:0] addr,data; input [3:0] strb; begin
    @(posedge clk); awaddr<=addr; awvalid<=1; wdata<=data; wstrb<=strb; wvalid<=0; bready<=1;
    @(posedge clk); awvalid<=0; wvalid<=1; @(posedge clk); wvalid<=0;
    while(!bvalid) @(posedge clk); @(posedge clk);
    if(strb==4'hf) cov_write_full=cov_write_full+1; else cov_write_byte=cov_write_byte+1; if(addr==0) cov_addr0=cov_addr0+1; if(addr==4) cov_addr4=cov_addr4+1;
  end endtask
  task axi_read; input [31:0] addr; output [31:0] data; begin
    @(posedge clk); araddr<=addr; arvalid<=1; rready<=1; @(posedge clk); arvalid<=0; while(!rvalid) @(posedge clk); data=rdata; cov_read=cov_read+1; @(posedge clk);
  end endtask
  reg [31:0] rd;
  task report_manual_coverage; begin
    $display("\n==== MANUAL COVERAGE: tb_axi_ram_manual ====");
    $display("write_full=%0d write_byte=%0d read=%0d bvalid=%0d rvalid=%0d addr0=%0d addr4=%0d",cov_write_full,cov_write_byte,cov_read,cov_bvalid,cov_rvalid,cov_addr0,cov_addr4);
    check(cov_write_full>0 && cov_write_byte>0,"coverage: full and partial writes"); check(cov_read>=2,"coverage: multiple reads"); check(cov_bvalid>0 && cov_rvalid>0,"coverage: AXI responses"); check(cov_addr0>0 && cov_addr4>0,"coverage: multiple addresses");
  end endtask
  initial begin
    errors=0; cov_write_full=0; cov_write_byte=0; cov_read=0; cov_bvalid=0; cov_rvalid=0; cov_addr0=0; cov_addr4=0;
    resetn=0; awaddr=0; wdata=0; araddr=0; wstrb=0; awvalid=0; wvalid=0; bready=0; arvalid=0; rready=0; repeat(4) @(posedge clk); resetn=1; repeat(2) @(posedge clk);
    axi_write(32'h0,32'h11223344,4'hf); axi_read(32'h0,rd); check(rd==32'h11223344,"AXI RAM full word write/read");
    axi_write(32'h4,32'haabbccdd,4'hf); axi_write(32'h4,32'h000000ee,4'h1); axi_read(32'h4,rd); check(rd[7:0]==8'hee && rd[31:8]==24'haabbcc,"AXI RAM byte strobe updates lane 0 only");
    report_manual_coverage(); if(errors==0) $display("\n[TB PASS] tb_axi_ram_manual"); else begin $display("\n[TB FAIL] errors=%0d",errors); $fatal; end $finish;
  end
endmodule
