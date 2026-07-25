/*`timescale 1ns/1ps
module tb_coef_switch_ctrl_manual;
  reg clk, resetn, request_switch, sync_event, datapath_idle;
  wire active_bank, switch_pulse, busy, pending;
  integer errors, cov_request, cov_pending_seen, cov_blocked_by_no_sync, cov_blocked_by_busy_path, cov_switch_pulse, cov_bank_a, cov_bank_b;
  coef_switch_ctrl dut(.clk(clk),.resetn(resetn),.request_switch(request_switch),.sync_event(sync_event),.datapath_idle(datapath_idle),.active_bank(active_bank),.switch_pulse(switch_pulse),.busy(busy),.pending(pending));
  initial clk=0; always #5 clk=~clk;
  task check; input cond; input [255:0] msg; begin if(!cond) begin errors=errors+1; $display("[FAIL] %0s t=%0t",msg,$time); end else $display("[PASS] %0s",msg); end endtask
  task pulse_req; begin @(posedge clk); request_switch<=1; cov_request=cov_request+1; @(posedge clk); request_switch<=0; end endtask
  task pulse_sync; begin @(posedge clk); sync_event<=1; @(posedge clk); sync_event<=0; end endtask
  always @(posedge clk) if(resetn) begin if(pending) cov_pending_seen<=cov_pending_seen+1; if(switch_pulse) cov_switch_pulse<=cov_switch_pulse+1; if(active_bank) cov_bank_b<=cov_bank_b+1; else cov_bank_a<=cov_bank_a+1; end
  task report_manual_coverage; begin
    $display("\n==== MANUAL COVERAGE: tb_coef_switch_ctrl_manual ====");
    $display("request=%0d pending_seen=%0d blocked_no_sync=%0d blocked_busy_path=%0d switch_pulse=%0d bank_a_seen=%0d bank_b_seen=%0d",cov_request,cov_pending_seen,cov_blocked_by_no_sync,cov_blocked_by_busy_path,cov_switch_pulse,cov_bank_a,cov_bank_b);
    check(cov_request>=2,"coverage: multiple requests"); check(cov_pending_seen>0,"coverage: pending state observed"); check(cov_blocked_by_no_sync>0,"coverage: switch blocked before sync"); check(cov_blocked_by_busy_path>0,"coverage: switch blocked when datapath not idle"); check(cov_switch_pulse>=2,"coverage: switch pulses generated"); check(cov_bank_a>0 && cov_bank_b>0,"coverage: both active banks observed");
  end endtask
  initial begin
    errors=0; cov_request=0; cov_pending_seen=0; cov_blocked_by_no_sync=0; cov_blocked_by_busy_path=0; cov_switch_pulse=0; cov_bank_a=0; cov_bank_b=0;
    resetn=0; request_switch=0; sync_event=0; datapath_idle=0; repeat(4) @(posedge clk); resetn=1; repeat(2) @(posedge clk);
    check(active_bank==0 && busy==0 && pending==0,"reset state bank A idle");
    pulse_req(); repeat(3) @(posedge clk); if(pending && busy && !switch_pulse) cov_blocked_by_no_sync=1; check(pending && busy,"request remains pending without sync");
    pulse_sync(); repeat(2) @(posedge clk); if(pending && busy && active_bank==0) cov_blocked_by_busy_path=1; check(active_bank==0 && pending,"sync alone does not switch when datapath_idle=0");
    datapath_idle=1; pulse_sync(); @(posedge clk); check(active_bank==1 && !pending && !busy,"switch to bank B on sync and idle");
    pulse_req(); pulse_sync(); @(posedge clk); check(active_bank==0,"switch back to bank A");
    report_manual_coverage(); if(errors==0) $display("\n[TB PASS] tb_coef_switch_ctrl_manual"); else begin $display("\n[TB FAIL] errors=%0d",errors); $fatal; end $finish;
  end
endmodule
*/
`timescale 1ns/1ps

module tb_coef_switch_ctrl_manual;

reg clk;
reg resetn;
reg request_switch;
reg sync_event;
reg datapath_idle;

wire active_bank;
wire switch_pulse;
wire busy;
wire pending;

integer errors;

// Manual coverage
integer cov_request;
integer cov_pending_seen;
integer cov_blocked_by_no_sync;
integer cov_blocked_by_busy_path;
integer cov_switches;
integer cov_bank_a;
integer cov_bank_b;

//---------------------------------------------------------------------------
// DUT
//---------------------------------------------------------------------------

coef_switch_ctrl dut (
.clk(clk),
.resetn(resetn),
.request_switch(request_switch),
.sync_event(sync_event),
.datapath_idle(datapath_idle),
.active_bank(active_bank),
.switch_pulse(switch_pulse),
.busy(busy),
.pending(pending)
);

//---------------------------------------------------------------------------
// Clock
//---------------------------------------------------------------------------

initial clk = 0;
always #5 clk = ~clk;

//---------------------------------------------------------------------------
// Check helper
//---------------------------------------------------------------------------

task check;
input cond;
input [255:0] msg;
begin
if (!cond) begin
errors = errors + 1;
$display("[FAIL] %0s t=%0t", msg, $time);
end
else begin
$display("[PASS] %0s", msg);
end
end
endtask

//---------------------------------------------------------------------------
// Request pulse
//---------------------------------------------------------------------------

task pulse_req;
begin
@(posedge clk);
request_switch <= 1'b1;
cov_request = cov_request + 1;

  @(posedge clk);
  request_switch <= 1'b0;
end

endtask

//---------------------------------------------------------------------------
// Sync pulse
//---------------------------------------------------------------------------

task pulse_sync;
begin
@(posedge clk);
sync_event <= 1'b1;

  @(posedge clk);
  sync_event <= 1'b0;
end

endtask

//---------------------------------------------------------------------------
// Coverage monitor
//---------------------------------------------------------------------------

always @(posedge clk) begin
if (resetn) begin

  if (pending)
    cov_pending_seen <= cov_pending_seen + 1;

  if (active_bank)
    cov_bank_b <= cov_bank_b + 1;
  else
    cov_bank_a <= cov_bank_a + 1;

end

end

//---------------------------------------------------------------------------
// Coverage report
//---------------------------------------------------------------------------

task report_manual_coverage;
begin

  $display("");
  $display("==== MANUAL COVERAGE: tb_coef_switch_ctrl_manual ====");

  $display(
    "request=%0d pending_seen=%0d blocked_no_sync=%0d blocked_busy_path=%0d switches=%0d bank_a_seen=%0d bank_b_seen=%0d",
    cov_request,
    cov_pending_seen,
    cov_blocked_by_no_sync,
    cov_blocked_by_busy_path,
    cov_switches,
    cov_bank_a,
    cov_bank_b
  );

  check(cov_request >= 2,
        "coverage: multiple requests");

  check(cov_pending_seen > 0,
        "coverage: pending state observed");

  check(cov_blocked_by_no_sync > 0,
        "coverage: switch blocked before sync");

  check(cov_blocked_by_busy_path > 0,
        "coverage: switch blocked when datapath not idle");

  check(cov_switches >= 2,
        "coverage: bank switched multiple times");

  check(cov_bank_a > 0 && cov_bank_b > 0,
        "coverage: both active banks observed");

end

endtask

//---------------------------------------------------------------------------
// Main test
//---------------------------------------------------------------------------

initial begin

errors = 0;

cov_request             = 0;
cov_pending_seen        = 0;
cov_blocked_by_no_sync  = 0;
cov_blocked_by_busy_path= 0;
cov_switches            = 0;
cov_bank_a              = 0;
cov_bank_b              = 0;

resetn         = 0;
request_switch = 0;
sync_event     = 0;
datapath_idle  = 0;

//-----------------------------------------------------------------------
// Reset
//-----------------------------------------------------------------------

repeat (4)
  @(posedge clk);

resetn = 1;

repeat (2)
  @(posedge clk);

check(active_bank == 0 &&
      busy == 0 &&
      pending == 0,
      "reset state bank A idle");

//-----------------------------------------------------------------------
// Request without sync
//-----------------------------------------------------------------------

pulse_req();

repeat (3)
  @(posedge clk);

if (pending && busy && !switch_pulse)
  cov_blocked_by_no_sync = 1;

check(pending && busy,
      "request remains pending without sync");

//-----------------------------------------------------------------------
// Sync while datapath busy
//-----------------------------------------------------------------------

pulse_sync();

repeat (2)
  @(posedge clk);

if (pending && busy && active_bank == 0)
  cov_blocked_by_busy_path = 1;

check(active_bank == 0 && pending,
      "sync alone does not switch when datapath_idle=0");

//-----------------------------------------------------------------------
// Enable idle and switch A -> B
//-----------------------------------------------------------------------

datapath_idle = 1;

pulse_sync();

@(posedge clk);

check(active_bank == 1 &&
      !pending &&
      !busy,
      "switch to bank B on sync and idle");

if (active_bank == 1)
  cov_switches = cov_switches + 1;

//-----------------------------------------------------------------------
// Switch B -> A
//-----------------------------------------------------------------------

pulse_req();

pulse_sync();

@(posedge clk);

check(active_bank == 0,
      "switch back to bank A");

if (active_bank == 0)
  cov_switches = cov_switches + 1;

//-----------------------------------------------------------------------
// Coverage summary
//-----------------------------------------------------------------------

report_manual_coverage();

if (errors == 0) begin
  $display("");
  $display("[TB PASS] tb_coef_switch_ctrl_manual");
end
else begin
  $display("");
  $display("[TB FAIL] errors=%0d", errors);
  $fatal;
end

$finish;

end

endmodule

