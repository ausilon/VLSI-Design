`timescale 1ns/1ps
module tb_axi_spi_manual;
  reg clk, resetn; reg [11:0] awaddr, araddr; reg awvalid,wvalid,bready,arvalid,rready; reg [31:0] wdata; reg [3:0] wstrb; wire awready,wready,bvalid,arready,rvalid; wire [31:0] rdata; wire [1:0] bresp,rresp; wire spi_sck, spi_mosi, spi_cs; reg spi_miso;
  integer errors, cov_axi_write, cov_status_read, cov_rx_read, cov_cs_low, cov_sck_toggle, cov_mosi_one, cov_mosi_zero, cov_bvalid, cov_rvalid;
  reg last_sck;
  axi_spi dut(.clk(clk),.resetn(resetn),.s_axi_awaddr(awaddr),.s_axi_awvalid(awvalid),.s_axi_awready(awready),.s_axi_wdata(wdata),.s_axi_wstrb(wstrb),.s_axi_wvalid(wvalid),.s_axi_wready(wready),.s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),.s_axi_araddr(araddr),.s_axi_arvalid(arvalid),.s_axi_arready(arready),.s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rvalid(rvalid),.s_axi_rready(rready),.spi_sck(spi_sck),.spi_mosi(spi_mosi),.spi_miso(spi_miso),.spi_cs(spi_cs));
  initial clk=0; always #5 clk=~clk;
  task check; input cond; input [255:0] msg; begin if(!cond) begin errors=errors+1; $display("[FAIL] %0s t=%0t rdata=%h",msg,$time,rdata); end else $display("[PASS] %0s",msg); end endtask
  always @(posedge clk) begin
    if(!resetn) begin last_sck<=0; end else begin
      if(bvalid) cov_bvalid<=cov_bvalid+1; if(rvalid) cov_rvalid<=cov_rvalid+1; if(!spi_cs) cov_cs_low<=cov_cs_low+1; if(last_sck != spi_sck) cov_sck_toggle<=cov_sck_toggle+1; if(spi_mosi) cov_mosi_one<=cov_mosi_one+1; else cov_mosi_zero<=cov_mosi_zero+1; last_sck<=spi_sck;
    end
  end
  always @(negedge spi_sck or negedge resetn) begin if(!resetn) spi_miso<=0; else spi_miso<=~spi_miso; end
  task axi_write; input [11:0] addr; input [31:0] data; begin @(posedge clk); awaddr<=addr; wdata<=data; awvalid<=1; wvalid<=1; bready<=1; @(posedge clk); awvalid<=0; wvalid<=0; while(!bvalid) @(posedge clk); @(posedge clk); if(addr==0) cov_axi_write=cov_axi_write+1; end endtask
  task axi_read; input [11:0] addr; output [31:0] data; begin @(posedge clk); araddr<=addr; arvalid<=1; rready<=1; @(posedge clk); data=rdata; arvalid<=0; if(addr==12'h8) cov_status_read=cov_status_read+1; if(addr==12'h4) cov_rx_read=cov_rx_read+1; @(posedge clk); end endtask
  reg [31:0] rd; integer guard;
  task report_manual_coverage; begin
    $display("\n==== MANUAL COVERAGE: tb_axi_spi_manual ====");
    $display("axi_write=%0d status_read=%0d rx_read=%0d cs_low=%0d sck_toggle=%0d mosi_one=%0d mosi_zero=%0d bvalid=%0d rvalid=%0d",cov_axi_write,cov_status_read,cov_rx_read,cov_cs_low,cov_sck_toggle,cov_mosi_one,cov_mosi_zero,cov_bvalid,cov_rvalid);
    check(cov_axi_write>0,"coverage: AXI SPI write"); check(cov_status_read>0 && cov_rx_read>0,"coverage: status/RX reads"); check(cov_cs_low>0 && cov_sck_toggle>=8,"coverage: SPI transaction activity"); check(cov_mosi_one>0 && cov_mosi_zero>0,"coverage: MOSI 0/1 seen"); check(cov_bvalid>0 && cov_rvalid>0,"coverage: AXI responses");
  end endtask
  initial begin
    errors=0; cov_axi_write=0; cov_status_read=0; cov_rx_read=0; cov_cs_low=0; cov_sck_toggle=0; cov_mosi_one=0; cov_mosi_zero=0; cov_bvalid=0; cov_rvalid=0;
    resetn=0; awaddr=0; araddr=0; awvalid=0; wvalid=0; bready=0; arvalid=0; rready=0; wdata=0; wstrb=4'hf; spi_miso=0; last_sck=0; repeat(4) @(posedge clk); resetn=1; repeat(4) @(posedge clk);
    axi_write(12'h0,32'h000000a5); repeat(400) @(posedge clk); axi_read(12'h8,rd); check(rd[0]==1'b1,"SPI status not busy after transfer"); axi_read(12'h4,rd); $display("[INFO] SPI RX_DATA=0x%02h",rd[7:0]);
    report_manual_coverage(); if(errors==0) $display("\n[TB PASS] tb_axi_spi_manual"); else begin $display("\n[TB FAIL] errors=%0d",errors); $fatal; end $finish;
  end
endmodule


