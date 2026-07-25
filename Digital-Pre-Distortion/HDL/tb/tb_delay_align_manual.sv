/*`timescale 1ns/1ps
module tb_delay_align_manual;
  localparam W=16; localparam D=8;
  reg clk, resetn, valid_in; reg [7:0] delay_cfg; reg signed [W-1:0] i_in, q_in; wire signed [W-1:0] i_out, q_out; wire valid_out;
  integer errors, cov_delay0, cov_delay3, cov_valid_in, cov_valid_out, cov_invalid_gap;
  delay_align #(.SAMPLE_WIDTH(W),.MAX_DELAY(D)) dut(.clk(clk),.resetn(resetn),.delay_cfg(delay_cfg),.i_in(i_in),.q_in(q_in),.valid_in(valid_in),.i_out(i_out),.q_out(q_out),.valid_out(valid_out));
  initial clk=0; always #5 clk=~clk;
  task check; input cond; input [255:0] msg; begin if(!cond) begin errors=errors+1; $display("[FAIL] %0s t=%0t i_out=%0d q_out=%0d valid=%0b",msg,$time,i_out,q_out,valid_out); end else $display("[PASS] %0s",msg); end endtask
  always @(posedge clk) if(resetn) begin if(valid_in) cov_valid_in<=cov_valid_in+1; if(valid_out) cov_valid_out<=cov_valid_out+1; end
  task drive; input integer i; input integer q; input v; begin @(posedge clk); i_in<=i; q_in<=q; valid_in<=v; if(!v) cov_invalid_gap=cov_invalid_gap+1; end endtask
  task report_manual_coverage; begin
    $display("\n==== MANUAL COVERAGE: tb_delay_align_manual ====");
    $display("delay0=%0d delay3=%0d valid_in=%0d valid_out=%0d invalid_gap=%0d",cov_delay0,cov_delay3,cov_valid_in,cov_valid_out,cov_invalid_gap);
    check(cov_delay0>0 && cov_delay3>0,"coverage: delay 0 and delay 3 paths"); check(cov_valid_in>0 && cov_valid_out>0,"coverage: valid propagated"); check(cov_invalid_gap>0,"coverage: invalid gap propagated");
  end endtask
  initial begin
    errors=0; cov_delay0=0; cov_delay3=0; cov_valid_in=0; cov_valid_out=0; cov_invalid_gap=0; resetn=0; delay_cfg=0; i_in=0; q_in=0; valid_in=0; repeat(4) @(posedge clk); resetn=1; repeat(2) @(posedge clk);
    delay_cfg=0; cov_delay0=1; drive(101,201,1); @(posedge clk); check(valid_out && i_out==101 && q_out==201,"delay 0 output appears after pipeline register latency");
    drive(0,0,0); @(posedge clk); check(!valid_out,"invalid gap clears valid_out with delay 0");
    delay_cfg=3; cov_delay3=1; drive(11,21,1); drive(12,22,1); drive(13,23,1); drive(14,24,1); @(posedge clk); check(valid_out && i_out==11 && q_out==21,"delay 3 returns first sample after expected latency");
    repeat(5) @(posedge clk); report_manual_coverage(); if(errors==0) $display("\n[TB PASS] tb_delay_align_manual"); else begin $display("\n[TB FAIL] errors=%0d",errors); $fatal; end $finish;
  end
endmodule
*/
`timescale 1ns/1ps

module tb_delay_align;

  localparam W = 16;
  localparam D = 8;

  //------------------------------------------------------------
  // DUT I/O
  //------------------------------------------------------------
  logic clk;
  logic resetn;

  logic [7:0] delay_cfg;

  logic signed [W-1:0] i_in;
  logic signed [W-1:0] q_in;
  logic valid_in;

  wire signed [W-1:0] i_out;
  wire signed [W-1:0] q_out;
  wire valid_out;

  delay_align #(
      .SAMPLE_WIDTH(W),
      .MAX_DELAY(D)
  ) dut (
      .clk(clk),
      .resetn(resetn),
      .delay_cfg(delay_cfg),
      .i_in(i_in),
      .q_in(q_in),
      .valid_in(valid_in),
      .i_out(i_out),
      .q_out(q_out),
      .valid_out(valid_out)
  );

  //------------------------------------------------------------
  // Clock
  //------------------------------------------------------------
  initial clk = 0;
  always #5 clk = ~clk;

  //------------------------------------------------------------
  // Scoreboard (modelo de referência)
  //------------------------------------------------------------

  logic signed [W-1:0] ref_i_pipe [0:D-1];
  logic signed [W-1:0] ref_q_pipe [0:D-1];
  logic                ref_v_pipe [0:D-1];

  logic signed [W-1:0] exp_i;
  logic signed [W-1:0] exp_q;
  logic                exp_v;

  integer k;
  integer errors;

  //------------------------------------------------------------
  // Cobertura manual
  //------------------------------------------------------------

  integer cov_delay0;
  integer cov_delay3;
  integer cov_valid;
  integer cov_invalid;

  //------------------------------------------------------------
  // Reference model
  //------------------------------------------------------------

  always @(posedge clk or negedge resetn) begin

    if(!resetn) begin

      for(k=0;k<D;k=k+1) begin
        ref_i_pipe[k] <= '0;
        ref_q_pipe[k] <= '0;
        ref_v_pipe[k] <= 0;
      end

      exp_i <= '0;
      exp_q <= '0;
      exp_v <= 0;

    end
    else begin

      ref_i_pipe[0] <= i_in;
      ref_q_pipe[0] <= q_in;
      ref_v_pipe[0] <= valid_in;

      for(k=1;k<D;k=k+1) begin
        ref_i_pipe[k] <= ref_i_pipe[k-1];
        ref_q_pipe[k] <= ref_q_pipe[k-1];
        ref_v_pipe[k] <= ref_v_pipe[k-1];
      end

      exp_i <= ref_i_pipe[delay_cfg];
      exp_q <= ref_q_pipe[delay_cfg];
      exp_v <= ref_v_pipe[delay_cfg];
    end
  end

  //------------------------------------------------------------
  // Checker
  //------------------------------------------------------------

  always @(posedge clk) begin

    if(resetn) begin

      if(i_out !== exp_i ||
         q_out !== exp_q ||
         valid_out !== exp_v) begin

        errors++;

        $display(
          "[FAIL] t=%0t cfg=%0d exp=(%0d,%0d,%0b) got=(%0d,%0d,%0b)",
          $time,
          delay_cfg,
          exp_i,
          exp_q,
          exp_v,
          i_out,
          q_out,
          valid_out
        );
      end

      if(valid_in)
        cov_valid++;

      if(!valid_in)
        cov_invalid++;

      if(delay_cfg==0)
        cov_delay0++;

      if(delay_cfg==3)
        cov_delay3++;
    end

  end

  //------------------------------------------------------------
  // Driver
  //------------------------------------------------------------

  task automatic drive(
      input integer i,
      input integer q,
      input bit     v
  );
  begin

    @(negedge clk);

    i_in    = i;
    q_in    = q;
    valid_in = v;

  end
  endtask

  //------------------------------------------------------------
  // Test sequence
  //------------------------------------------------------------

  initial begin

    errors = 0;

    cov_delay0 = 0;
    cov_delay3 = 0;
    cov_valid  = 0;
    cov_invalid= 0;

    i_in = 0;
    q_in = 0;
    valid_in = 0;
    delay_cfg = 0;

    resetn = 0;

    repeat(5) @(posedge clk);

    resetn = 1;

    //--------------------------------------------------------
    // delay = 0
    //--------------------------------------------------------

    delay_cfg = 0;

    drive(100,200,1);
    drive(101,201,1);
    drive(102,202,1);

    //--------------------------------------------------------
    // invalid gap
    //--------------------------------------------------------

    drive(0,0,0);

    //--------------------------------------------------------
    // delay = 3
    //--------------------------------------------------------

    delay_cfg = 3;

    drive(11,21,1);
    drive(12,22,1);
    drive(13,23,1);
    drive(14,24,1);
    drive(15,25,1);

    //--------------------------------------------------------
    // Random traffic
    //--------------------------------------------------------

    repeat(100) begin

      @(negedge clk);

      i_in     = $random;
      q_in     = $random;
      valid_in = $urandom_range(0,1);

      delay_cfg = $urandom_range(0,D-1);

    end

    //--------------------------------------------------------
    // Flush pipeline
    //--------------------------------------------------------

    repeat(D+5)
      @(posedge clk);

    //--------------------------------------------------------
    // Coverage report
    //--------------------------------------------------------

    $display("");
    $display("===== COVERAGE =====");
    $display("delay0    = %0d", cov_delay0);
    $display("delay3    = %0d", cov_delay3);
    $display("valid     = %0d", cov_valid);
    $display("invalid   = %0d", cov_invalid);

    if(errors == 0)
      $display("\n[TB PASS]");
    else begin
      $display("\n[TB FAIL] errors=%0d", errors);
      $fatal;
    end

    $finish;

  end

endmodule