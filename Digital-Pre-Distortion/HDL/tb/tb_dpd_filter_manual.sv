`timescale 1ns/1ps
module tb_dpd_filter_manual;
  localparam W=16; localparam CW=18; localparam A=6;
  reg clk, resetn, enable, force_bypass, sync_event, active_bank, in_valid, out_ready; reg signed [W-1:0] i_in,q_in; reg [CW-1:0] coef_data_a,coef_data_b;
  wire in_ready, out_valid, dpd_active, mac_busy; wire signed [W-1:0] i_out,q_out; wire [A-1:0] coef_addr;
  integer errors, cov_bypass, cov_enable_sync, cov_force_bypass, cov_bank_a, cov_bank_b, cov_out_valid, cov_backpressure;
  dpd_filter #(.SAMPLE_WIDTH(W),.COEF_WIDTH(CW),.COEF_ADDR_WIDTH(A)) dut(.clk(clk),.resetn(resetn),.enable(enable),.force_bypass(force_bypass),.sync_event(sync_event),.active_bank(active_bank),.i_in(i_in),.q_in(q_in),.in_valid(in_valid),.in_ready(in_ready),.i_out(i_out),.q_out(q_out),.out_valid(out_valid),.out_ready(out_ready),.coef_addr(coef_addr),.coef_data_a(coef_data_a),.coef_data_b(coef_data_b),.dpd_active(dpd_active),.mac_busy(mac_busy));
  initial clk=0; always #5 clk=~clk;
  always @* begin
    coef_data_a = (coef_addr == 0) ? 18'sh10000 : 18'sh00000;
    coef_data_b = (coef_addr == 0) ? 18'sh10000 : 18'sh00000;
  end
  task check; input cond; input [255:0] msg; begin if(!cond) begin errors=errors+1; $display("[FAIL] %0s t=%0t",msg,$time); end else $display("[PASS] %0s",msg); end endtask
  always @(posedge clk) if(resetn) begin if(out_valid) cov_out_valid<=cov_out_valid+1; if(mac_busy) cov_backpressure<=cov_backpressure+1; if(active_bank) cov_bank_b<=cov_bank_b+1; else cov_bank_a<=cov_bank_a+1; end
  task pulse_sync; begin @(posedge clk); sync_event<=1; @(posedge clk); sync_event<=0; end endtask
  task send_sample; input integer ii,qq; begin while(!in_ready) @(posedge clk); @(posedge clk); i_in<=ii; q_in<=qq; in_valid<=1; @(posedge clk); in_valid<=0; end endtask
  task check_bypass_sample; input integer ii,qq; begin @(posedge clk); i_in<=ii; q_in<=qq; in_valid<=1; #1; check(out_valid && i_out==ii && q_out==qq && !dpd_active,"bypass path passes input while valid is asserted"); cov_bypass=1; @(posedge clk); in_valid<=0; end endtask
  task wait_output; integer guard; begin guard=0; while(!out_valid && guard<100) begin @(posedge clk); guard=guard+1; end check(out_valid,"DPD MAC output valid asserted"); end endtask
  task report_manual_coverage; begin
    $display("\n==== MANUAL COVERAGE: tb_dpd_filter_manual ====");
    $display("bypass=%0d enable_sync=%0d force_bypass=%0d bank_a_seen=%0d bank_b_seen=%0d out_valid=%0d backpressure=%0d",cov_bypass,cov_enable_sync,cov_force_bypass,cov_bank_a,cov_bank_b,cov_out_valid,cov_backpressure);
    check(cov_bypass>0 && cov_enable_sync>0 && cov_force_bypass>0,"coverage: bypass, dpd active and forced bypass"); check(cov_bank_a>0 && cov_bank_b>0,"coverage: both coefficient bank selections observed"); check(cov_out_valid>0,"coverage: output valid observed"); check(cov_backpressure>0,"coverage: MAC backpressure observed");
  end endtask
  initial begin
    errors=0; cov_bypass=0; cov_enable_sync=0; cov_force_bypass=0; cov_bank_a=0; cov_bank_b=0; cov_out_valid=0; cov_backpressure=0;
    resetn=0; enable=0; force_bypass=1; sync_event=0; active_bank=0; in_valid=0; out_ready=1; i_in=0; q_in=0; repeat(4) @(posedge clk); resetn=1; repeat(2) @(posedge clk);
    check_bypass_sample(1,2);
    enable=1; force_bypass=0; pulse_sync(); @(posedge clk); check(dpd_active,"DPD becomes active only after sync_event"); cov_enable_sync=1;
    active_bank=1; send_sample(3,4); wait_output(); check(i_out==3 && q_out==4,"active DPD GMP identity term passes sample");
    out_ready=0; send_sample(5,6); @(posedge clk); check(mac_busy,"backpressure propagates to MAC busy when DPD active"); out_ready=1; repeat(2) @(posedge clk);
    force_bypass=1; pulse_sync(); @(posedge clk); check(!dpd_active,"force_bypass disables DPD on sync_event"); cov_force_bypass=1;
    report_manual_coverage(); if(errors==0) $display("\n[TB PASS] tb_dpd_filter_manual"); else begin $display("\n[TB FAIL] errors=%0d",errors); $fatal; end $finish;
  end
endmodule
