`timescale 1ns/1ps
module tb_axi_lite_regs_manual;
  reg clk, resetn;
  reg [11:0] awaddr, araddr; reg awvalid,wvalid,bready,arvalid,rready; reg [31:0] wdata; reg [3:0] wstrb;
  wire awready,wready,bvalid,arready,rvalid; wire [1:0] bresp,rresp; wire [31:0] rdata;
  wire enable, force_bypass, capture_start_pulse, coef_switch_req_pulse, irq_clear_pulse, coef_we_a_pulse, coef_we_b_pulse;
  wire [31:0] threshold_error, threshold_clip, threshold_drift, irq_mask, irq_w1c; wire [9:0] capture_len; wire [7:0] feedback_delay; wire [9:0] capture_rd_addr; wire [5:0] coef_addr; wire [17:0] coef_wdata;
  reg [17:0] coef_rdata_a, coef_rdata_b; reg dpd_active,capture_busy,capture_done,coef_switch_busy,active_bank,irq; reg [31:0] irq_status,metric_power,metric_error,metric_clipping,metric_drift;
  reg [63:0] capture_rd_data;
  integer errors, cov_wr_control, cov_wr_threshold, cov_wr_coef, cov_wr_capture_delay, cov_rd_status, cov_w1p_capture, cov_w1p_switch, cov_w1p_clear, cov_w1c, cov_coef_we_a, cov_coef_we_b;
  axi_lite_regs dut(.clk(clk),.resetn(resetn),.s_axi_awaddr(awaddr),.s_axi_awvalid(awvalid),.s_axi_awready(awready),.s_axi_wdata(wdata),.s_axi_wstrb(wstrb),.s_axi_wvalid(wvalid),.s_axi_wready(wready),.s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),.s_axi_araddr(araddr),.s_axi_arvalid(arvalid),.s_axi_arready(arready),.s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rvalid(rvalid),.s_axi_rready(rready),.enable(enable),.force_bypass(force_bypass),.capture_start_pulse(capture_start_pulse),.coef_switch_req_pulse(coef_switch_req_pulse),.irq_clear_pulse(irq_clear_pulse),.threshold_error(threshold_error),.threshold_clip(threshold_clip),.threshold_drift(threshold_drift),.capture_len(capture_len),.feedback_delay(feedback_delay),.capture_rd_addr(capture_rd_addr),.capture_rd_data(capture_rd_data),.coef_we_a_pulse(coef_we_a_pulse),.coef_we_b_pulse(coef_we_b_pulse),.coef_addr(coef_addr),.coef_wdata(coef_wdata),.coef_rdata_a(coef_rdata_a),.coef_rdata_b(coef_rdata_b),.dpd_active(dpd_active),.capture_busy(capture_busy),.capture_done(capture_done),.coef_switch_busy(coef_switch_busy),.active_bank(active_bank),.irq(irq),.irq_status(irq_status),.metric_power(metric_power),.metric_error(metric_error),.metric_clipping(metric_clipping),.metric_drift(metric_drift),.irq_mask(irq_mask),.irq_w1c(irq_w1c));
  initial clk=0; always #5 clk=~clk;
  task check; input cond; input [255:0] msg; begin if(!cond) begin errors=errors+1; $display("[FAIL] %0s t=%0t rdata=%h",msg,$time,rdata); end else $display("[PASS] %0s",msg); end endtask
  task axi_write; input [11:0] addr; input [31:0] data; begin
    @(posedge clk); awaddr<=addr; wdata<=data; awvalid<=1; wvalid<=1; bready<=1; @(posedge clk); awvalid<=0; wvalid<=0; while(!bvalid) @(posedge clk); @(posedge clk); if(addr==12'h000) cov_wr_control=cov_wr_control+1; if(addr>=12'h020 && addr<=12'h028) cov_wr_threshold=cov_wr_threshold+1; if(addr>=12'h030 && addr<=12'h038) cov_wr_coef=cov_wr_coef+1; if(addr==12'h050 || addr==12'h054) cov_wr_capture_delay=cov_wr_capture_delay+1; if(addr==12'h008) cov_w1c=cov_w1c+1;
  end endtask
  task axi_read; input [11:0] addr; output [31:0] data; begin
    @(posedge clk); araddr<=addr; arvalid<=1; rready<=1; @(posedge clk); arvalid<=0; while(!rvalid) @(posedge clk); data=rdata; if(addr==12'h004) cov_rd_status=cov_rd_status+1; @(posedge clk);
  end endtask
  always @(posedge clk) if(resetn) begin if(capture_start_pulse) cov_w1p_capture<=cov_w1p_capture+1; if(coef_switch_req_pulse) cov_w1p_switch<=cov_w1p_switch+1; if(irq_clear_pulse) cov_w1p_clear<=cov_w1p_clear+1; if(coef_we_a_pulse) cov_coef_we_a<=cov_coef_we_a+1; if(coef_we_b_pulse) cov_coef_we_b<=cov_coef_we_b+1; end
  reg [31:0] rd;
  task report_manual_coverage; begin
    $display("\n==== MANUAL COVERAGE: tb_axi_lite_regs_manual ====");
    $display("wr_control=%0d wr_threshold=%0d wr_coef=%0d wr_capture_delay=%0d rd_status=%0d w1p_capture=%0d w1p_switch=%0d w1p_clear=%0d w1c=%0d coef_we_a=%0d coef_we_b=%0d",cov_wr_control,cov_wr_threshold,cov_wr_coef,cov_wr_capture_delay,cov_rd_status,cov_w1p_capture,cov_w1p_switch,cov_w1p_clear,cov_w1c,cov_coef_we_a,cov_coef_we_b);
    check(cov_wr_control>0 && cov_wr_threshold>=3 && cov_wr_coef>=3 && cov_wr_capture_delay>=2,"coverage: main register write groups"); check(cov_rd_status>0,"coverage: status read"); check(cov_w1p_capture>0 && cov_w1p_switch>0 && cov_w1p_clear>0,"coverage: W1P control pulses"); check(cov_w1c>0,"coverage: IRQ W1C write"); check(cov_coef_we_a>0 && cov_coef_we_b>0,"coverage: coefficient write pulses A/B");
  end endtask
  initial begin
    errors=0; cov_wr_control=0; cov_wr_threshold=0; cov_wr_coef=0; cov_wr_capture_delay=0; cov_rd_status=0; cov_w1p_capture=0; cov_w1p_switch=0; cov_w1p_clear=0; cov_w1c=0; cov_coef_we_a=0; cov_coef_we_b=0;
    resetn=0; awaddr=0; araddr=0; awvalid=0; wvalid=0; bready=0; arvalid=0; rready=0; wdata=0; wstrb=4'hf; coef_rdata_a=18'h15555; coef_rdata_b=18'h2aaaa; capture_rd_data=64'h1111_2222_3333_4444; dpd_active=1; capture_busy=1; capture_done=1; coef_switch_busy=1; active_bank=1; irq=1; irq_status=32'h5; metric_power=100; metric_error=200; metric_clipping=3; metric_drift=400;
    repeat(4) @(posedge clk); resetn=1; repeat(2) @(posedge clk); check(!enable && force_bypass,"reset default control values");
    axi_write(12'h000,32'h0000_001f); @(posedge clk); check(enable && force_bypass,"control register sets enable and force_bypass");
    axi_write(12'h020,32'd123); axi_write(12'h024,32'd4); axi_write(12'h028,32'd456); check(threshold_error==123 && threshold_clip==4 && threshold_drift==456,"threshold registers update");
    axi_write(12'h030,32'd17); axi_write(12'h034,32'h0002_abcd); axi_write(12'h038,32'h3); check(coef_addr==17 && coef_wdata==18'h2abcd,"coefficient addr/data update");
    axi_write(12'h050,32'd77); axi_write(12'h054,32'd9); axi_write(12'h058,32'd12); check(capture_len==77 && feedback_delay==9 && capture_rd_addr==12,"capture length, delay and read address update");
    axi_write(12'h008,32'h0000_0005); @(posedge clk); check(irq_w1c==0,"irq_w1c is a one-cycle pulse and returns to zero");
    axi_read(12'h004,rd); check(rd[5:0]==6'b111111,"status register reflects external status inputs");
    axi_read(12'h03c,rd); check(rd[17:0]==18'h15555,"coef_rdata_a readback"); axi_read(12'h040,rd); check(rd[17:0]==18'h2aaaa,"coef_rdata_b readback");
    axi_read(12'h05c,rd); check(rd==32'h3333_4444,"capture read low word"); axi_read(12'h060,rd); check(rd==32'h1111_2222,"capture read high word");
    report_manual_coverage(); if(errors==0) $display("\n[TB PASS] tb_axi_lite_regs_manual"); else begin $display("\n[TB FAIL] errors=%0d",errors); $fatal; end $finish;
  end
endmodule
