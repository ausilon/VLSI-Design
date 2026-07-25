`timescale 1ns/1ps
module tb_irq_status_ctrl_manual;
  reg clk, resetn, clear_pulse, capture_done, coef_switch_done, metrics_valid;
  reg [31:0] w1c, mask, metric_error, metric_clipping, metric_drift, threshold_error, threshold_clip, threshold_drift;
  wire [31:0] status; wire irq, retrain_request;
  integer errors, cov_capture_done, cov_coef_done, cov_metric_error, cov_metric_clip, cov_metric_drift, cov_irq_assert, cov_w1c, cov_clear;
  irq_status_ctrl dut(.clk(clk),.resetn(resetn),.clear_pulse(clear_pulse),.w1c(w1c),.mask(mask),.capture_done(capture_done),.coef_switch_done(coef_switch_done),.metrics_valid(metrics_valid),.metric_error(metric_error),.metric_clipping(metric_clipping),.metric_drift(metric_drift),.threshold_error(threshold_error),.threshold_clip(threshold_clip),.threshold_drift(threshold_drift),.status(status),.irq(irq),.retrain_request(retrain_request));
  initial clk=0; always #5 clk=~clk;
  task check; input cond; input [255:0] msg; begin if(!cond) begin errors=errors+1; $display("[FAIL] %0s t=%0t status=%h",msg,$time,status); end else $display("[PASS] %0s",msg); end endtask
  task pulse_cap; begin @(posedge clk); capture_done<=1; @(posedge clk); capture_done<=0; cov_capture_done=cov_capture_done+1; end endtask
  task pulse_coef; begin @(posedge clk); coef_switch_done<=1; @(posedge clk); coef_switch_done<=0; cov_coef_done=cov_coef_done+1; end endtask
  task pulse_metrics; input [31:0] e,c,d; begin @(posedge clk); metric_error<=e; metric_clipping<=c; metric_drift<=d; metrics_valid<=1; @(posedge clk); metrics_valid<=0; if(e>threshold_error) cov_metric_error=cov_metric_error+1; if(c>threshold_clip) cov_metric_clip=cov_metric_clip+1; if(d>threshold_drift) cov_metric_drift=cov_metric_drift+1; end endtask
  always @(posedge clk) if(resetn && irq) cov_irq_assert<=cov_irq_assert+1;
  task report_manual_coverage; begin
    $display("\n==== MANUAL COVERAGE: tb_irq_status_ctrl_manual ====");
    $display("capture_done=%0d coef_done=%0d metric_error=%0d metric_clip=%0d metric_drift=%0d irq_assert=%0d w1c=%0d clear=%0d", cov_capture_done,cov_coef_done,cov_metric_error,cov_metric_clip,cov_metric_drift,cov_irq_assert,cov_w1c,cov_clear);
    check(cov_capture_done>0 && cov_coef_done>0,"coverage: event bits 0/1"); check(cov_metric_error>0 && cov_metric_clip>0 && cov_metric_drift>0,"coverage: all metric threshold paths"); check(cov_irq_assert>0,"coverage: IRQ asserted"); check(cov_w1c>0 && cov_clear>0,"coverage: W1C and clear paths");
  end endtask
  initial begin
    errors=0; cov_capture_done=0; cov_coef_done=0; cov_metric_error=0; cov_metric_clip=0; cov_metric_drift=0; cov_irq_assert=0; cov_w1c=0; cov_clear=0;
    resetn=0; clear_pulse=0; w1c=0; mask=32'h7; capture_done=0; coef_switch_done=0; metrics_valid=0; metric_error=0; metric_clipping=0; metric_drift=0; threshold_error=10; threshold_clip=2; threshold_drift=30;
    repeat(4) @(posedge clk); resetn=1; repeat(2) @(posedge clk); check(status==0 && irq==0,"reset clears status and IRQ");
    pulse_cap(); @(posedge clk); check(status[0] && irq,"capture_done sets status[0] and IRQ");
    pulse_coef(); @(posedge clk); check(status[1],"coef_switch_done sets status[1]");
    pulse_metrics(11,1,0); @(posedge clk); check(status[2] && retrain_request,"metric_error above threshold sets retrain");
    w1c=32'h1; cov_w1c=1; @(posedge clk); w1c=0; @(posedge clk); check(!status[0] && status[1] && status[2],"W1C clears only selected bit");
    clear_pulse=1; cov_clear=1; @(posedge clk); clear_pulse=0; @(posedge clk); check(status==0,"clear_pulse clears all status");
    pulse_metrics(0,3,0); pulse_metrics(0,0,31); @(posedge clk); check(status[2],"clip/drift metrics set retrain bit");
    report_manual_coverage(); if(errors==0) $display("\n[TB PASS] tb_irq_status_ctrl_manual"); else begin $display("\n[TB FAIL] errors=%0d",errors); $fatal; end $finish;
  end
endmodule
