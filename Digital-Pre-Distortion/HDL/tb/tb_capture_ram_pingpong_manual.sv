/*`timescale 1ns/1ps
module tb_capture_ram_pingpong_manual;
  localparam W=16; localparam A=4;
  reg clk, resetn, start, sample_valid;
  reg [A-1:0] capture_len;
  reg signed [W-1:0] ref_i, ref_q, fb_i, fb_q;
  wire busy, done, active_page;
  integer errors, cov_start, cov_busy, cov_done, cov_page0, cov_page1, cov_samples;
  capture_ram_pingpong #(.SAMPLE_WIDTH(W),.ADDR_WIDTH(A)) dut(.clk(clk),.resetn(resetn),.start(start),.capture_len(capture_len),.ref_i(ref_i),.ref_q(ref_q),.fb_i(fb_i),.fb_q(fb_q),.sample_valid(sample_valid),.busy(busy),.done(done),.active_page(active_page));
  initial clk=0; always #5 clk=~clk;
  task check; input cond; input [255:0] msg; begin if(!cond) begin errors=errors+1; $display("[FAIL] %0s t=%0t",msg,$time); end else $display("[PASS] %0s",msg); end endtask
  always @(posedge clk) if(resetn) begin if(busy) cov_busy<=cov_busy+1; if(done) cov_done<=cov_done+1; if(active_page) cov_page1<=cov_page1+1; else cov_page0<=cov_page0+1; end
  task pulse_start; begin @(posedge clk); start<=1; cov_start=cov_start+1; @(posedge clk); start<=0; end endtask
  task send_sample; input integer idx; begin @(posedge clk); ref_i<=idx; ref_q<=idx+10; fb_i<=idx+20; fb_q<=idx+30; sample_valid<=1; cov_samples=cov_samples+1; @(posedge clk); sample_valid<=0; end endtask
  task run_capture; input [A-1:0] len; integer n; begin
    capture_len=len; pulse_start(); check(busy,"capture enters busy after start");
    for(n=0; n<=len; n=n+1) send_sample(n);
    @(posedge clk); check(done && !busy,"capture done after capture_len+1 valid samples");
  end endtask
  task report_manual_coverage; begin
    $display("\n==== MANUAL COVERAGE: tb_capture_ram_pingpong_manual ====");
    $display("start=%0d busy_cycles=%0d done_cycles=%0d page0_seen=%0d page1_seen=%0d samples=%0d", cov_start,cov_busy,cov_done,cov_page0,cov_page1,cov_samples);
    check(cov_start>=2,"coverage: multiple captures"); check(cov_busy>0 && cov_done>0,"coverage: busy and done observed"); check(cov_page0>0 && cov_page1>0,"coverage: both ping-pong pages observed"); check(cov_samples>=6,"coverage: multiple samples captured");
  end endtask
  initial begin
    errors=0; cov_start=0; cov_busy=0; cov_done=0; cov_page0=0; cov_page1=0; cov_samples=0; resetn=0; start=0; sample_valid=0; capture_len=0; ref_i=0; ref_q=0; fb_i=0; fb_q=0;
    repeat(4) @(posedge clk); resetn=1; repeat(2) @(posedge clk); check(!busy && !done && !active_page,"reset state idle page 0");
    run_capture(4'd2); run_capture(4'd3);
    report_manual_coverage(); if(errors==0) $display("\n[TB PASS] tb_capture_ram_pingpong_manual"); else begin $display("\n[TB FAIL] errors=%0d",errors); $fatal; end $finish;
  end
endmodule
*/
`timescale 1ns/1ps

module tb_capture_ram_pingpong_manual;

localparam W = 16;
localparam A = 4;

reg clk;
reg resetn;
reg start;
reg sample_valid;

reg [A-1:0] capture_len;

reg signed [W-1:0] ref_i;
reg signed [W-1:0] ref_q;
reg signed [W-1:0] fb_i;
reg signed [W-1:0] fb_q;

wire busy;
wire done;
wire active_page;
reg [A-1:0] rd_addr;
wire [4*W-1:0] rd_data;

integer errors;

// Manual coverage counters
integer cov_start;
integer cov_busy;
integer cov_done;
integer cov_page0;
integer cov_page1;
integer cov_samples;

capture_ram_pingpong #(
.SAMPLE_WIDTH(W),
.ADDR_WIDTH(A)
) dut (
.clk(clk),
.resetn(resetn),
.start(start),
.capture_len(capture_len),
.ref_i(ref_i),
.ref_q(ref_q),
.fb_i(fb_i),
.fb_q(fb_q),
.sample_valid(sample_valid),
.rd_addr(rd_addr),
.rd_data(rd_data),
.busy(busy),
.done(done),
.active_page(active_page)
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
$display("[FAIL] %0s  t=%0t", msg, $time);
end
else begin
$display("[PASS] %0s", msg);
end
end
endtask

//---------------------------------------------------------------------------
// Coverage collection
//---------------------------------------------------------------------------

always @(posedge clk) begin
if (resetn) begin

  if (busy)
    cov_busy <= cov_busy + 1;

  if (done)
    cov_done <= cov_done + 1;

  if (active_page)
    cov_page1 <= cov_page1 + 1;
  else
    cov_page0 <= cov_page0 + 1;

end

end

//---------------------------------------------------------------------------
// Start pulse
//---------------------------------------------------------------------------

task pulse_start;
begin
@(posedge clk);
start <= 1'b1;
cov_start = cov_start + 1;

  @(posedge clk);
  start <= 1'b0;
end

endtask

//---------------------------------------------------------------------------
// Send one valid sample
//---------------------------------------------------------------------------

task send_sample;
input integer idx;
begin

  @(posedge clk);

  ref_i <= idx;
  ref_q <= idx + 10;
  fb_i  <= idx + 20;
  fb_q  <= idx + 30;

  sample_valid <= 1'b1;
  cov_samples  = cov_samples + 1;

  @(posedge clk);
  sample_valid <= 1'b0;

end

endtask

//---------------------------------------------------------------------------
// Execute one capture
//---------------------------------------------------------------------------

task run_capture;
input [A-1:0] len;
integer n;
reg [4*W-1:0] expected;

begin

  capture_len = len;

  pulse_start();

  // Give DUT one cycle to settle after start
  @(posedge clk);

  check(busy,
        "capture enters busy after start");

  for (n = 0; n <= len; n = n + 1)
    send_sample(n);

  @(posedge clk);

  check(done && !busy,
        "capture done after capture_len+1 valid samples");

  rd_addr = len;
  #1;
  expected = {
    {12'd0, len},
    ({12'd0, len} + 16'd10),
    ({12'd0, len} + 16'd20),
    ({12'd0, len} + 16'd30)
  };
  check(rd_data == expected,
        "read port returns last sample from completed page");

end

endtask

//---------------------------------------------------------------------------
// Coverage report
//---------------------------------------------------------------------------

task report_manual_coverage;
begin

  $display("");
  $display("==== MANUAL COVERAGE: tb_capture_ram_pingpong_manual ====");

  $display(
    "start=%0d busy_cycles=%0d done_cycles=%0d page0_seen=%0d page1_seen=%0d samples=%0d",
    cov_start,
    cov_busy,
    cov_done,
    cov_page0,
    cov_page1,
    cov_samples
  );

  check(cov_start >= 2,
        "coverage: multiple captures");

  check(cov_busy > 0 && cov_done > 0,
        "coverage: busy and done observed");

  check(cov_page0 > 0 && cov_page1 > 0,
        "coverage: both ping-pong pages observed");

  check(cov_samples >= 6,
        "coverage: multiple samples captured");

end

endtask

//---------------------------------------------------------------------------
// Test sequence
//---------------------------------------------------------------------------

initial begin

errors = 0;

cov_start   = 0;
cov_busy    = 0;
cov_done    = 0;
cov_page0   = 0;
cov_page1   = 0;
cov_samples = 0;

resetn       = 0;
start        = 0;
sample_valid = 0;
rd_addr = 0;

capture_len = 0;

ref_i = 0;
ref_q = 0;
fb_i  = 0;
fb_q  = 0;

repeat (4)
  @(posedge clk);

resetn = 1;

repeat (2)
  @(posedge clk);

check(!busy && !done && !active_page,
      "reset state idle page 0");

run_capture(4'd2);

run_capture(4'd3);

report_manual_coverage();

if (errors == 0) begin
  $display("");
  $display("[TB PASS] tb_capture_ram_pingpong_manual");
end
else begin
  $display("");
  $display("[TB FAIL] errors=%0d", errors);
  $fatal;
end

$finish;

end

endmodule
