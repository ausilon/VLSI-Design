`timescale 1ns/1ps

module tb_dpd_top_dataset_manual;
  localparam W = 16;
  localparam CW = 18;
  localparam DATASET_N = 32;
  localparam CAPTURE_N = 30;

  localparam REG_CONTROL       = 12'h000;
  localparam REG_STATUS        = 12'h004;
  localparam REG_IRQ_STATUS    = 12'h008;
  localparam REG_THRESH_ERROR  = 12'h020;
  localparam REG_THRESH_CLIP   = 12'h024;
  localparam REG_THRESH_DRIFT  = 12'h028;
  localparam REG_COEF_ADDR     = 12'h030;
  localparam REG_COEF_WDATA    = 12'h034;
  localparam REG_COEF_CTRL     = 12'h038;
  localparam REG_COEF_RDATA_B  = 12'h040;
  localparam REG_CAPTURE_CTRL  = 12'h050;
  localparam REG_DELAY_CTRL    = 12'h054;
  localparam REG_CAPTURE_ADDR  = 12'h058;
  localparam REG_CAPTURE_LO    = 12'h05c;
  localparam REG_CAPTURE_HI    = 12'h060;

  localparam CTRL_ENABLE       = 32'h0000_0001;
  localparam CTRL_FORCE_BYPASS = 32'h0000_0002;
  localparam CTRL_CAPTURE      = 32'h0000_0004;
  localparam CTRL_COEF_SWITCH  = 32'h0000_0008;

  reg clk;
  reg resetn;

  reg [11:0] awaddr;
  reg awvalid;
  wire awready;
  reg [31:0] wdata;
  reg [3:0] wstrb;
  reg wvalid;
  wire wready;
  wire [1:0] bresp;
  wire bvalid;
  reg bready;

  reg [11:0] araddr;
  reg arvalid;
  wire arready;
  wire [31:0] rdata;
  wire [1:0] rresp;
  wire rvalid;
  reg rready;

  reg signed [W-1:0] sample_i_in;
  reg signed [W-1:0] sample_q_in;
  reg sample_valid_in;
  wire sample_ready_out;

  reg signed [W-1:0] feedback_i_in;
  reg signed [W-1:0] feedback_q_in;
  reg feedback_valid_in;
  reg sync_event;

  wire signed [W-1:0] sample_i_out;
  wire signed [W-1:0] sample_q_out;
  wire sample_valid_out;
  reg sample_ready_in;

  wire train_request;
  wire [3:0] supervisor_state;
  wire dpd_active;
  wire irq;

  reg [31:0] ref_mem [0:DATASET_N-1];
  reg [31:0] fb_mem [0:DATASET_N-1];
  reg [31:0] exp_hi [0:CAPTURE_N-1];
  reg [31:0] exp_lo [0:CAPTURE_N-1];

  integer errors;
  integer cov_dataset_loaded;
  integer cov_capture_read;
  integer cov_coef_write;
  integer cov_switch;
  integer cov_retrain;

  dpd_top dut (
    .clk(clk),
    .resetn(resetn),
    .s_axi_awaddr(awaddr),
    .s_axi_awvalid(awvalid),
    .s_axi_awready(awready),
    .s_axi_wdata(wdata),
    .s_axi_wstrb(wstrb),
    .s_axi_wvalid(wvalid),
    .s_axi_wready(wready),
    .s_axi_bresp(bresp),
    .s_axi_bvalid(bvalid),
    .s_axi_bready(bready),
    .s_axi_araddr(araddr),
    .s_axi_arvalid(arvalid),
    .s_axi_arready(arready),
    .s_axi_rdata(rdata),
    .s_axi_rresp(rresp),
    .s_axi_rvalid(rvalid),
    .s_axi_rready(rready),
    .sample_i_in(sample_i_in),
    .sample_q_in(sample_q_in),
    .sample_valid_in(sample_valid_in),
    .sample_ready_out(sample_ready_out),
    .feedback_i_in(feedback_i_in),
    .feedback_q_in(feedback_q_in),
    .feedback_valid_in(feedback_valid_in),
    .sync_event(sync_event),
    .sample_i_out(sample_i_out),
    .sample_q_out(sample_q_out),
    .sample_valid_out(sample_valid_out),
    .sample_ready_in(sample_ready_in),
    .train_request(train_request),
    .supervisor_state(supervisor_state),
    .dpd_active(dpd_active),
    .irq(irq)
  );

  initial clk = 0;
  always #5 clk = ~clk;

  task check;
    input cond;
    input [255:0] msg;
    begin
      if (!cond) begin
        errors = errors + 1;
        $display("[FAIL] %0s t=%0t", msg, $time);
      end else begin
        $display("[PASS] %0s", msg);
      end
    end
  endtask

  task axi_write;
    input [11:0] addr;
    input [31:0] data;
    integer guard;
    begin
      @(posedge clk);
      awaddr <= addr;
      wdata <= data;
      wstrb <= 4'hf;
      awvalid <= 1;
      wvalid <= 1;
      bready <= 1;

      guard = 0;
      while (!(awready && wready) && guard < 100) begin
        @(posedge clk);
        guard = guard + 1;
      end

      @(posedge clk);
      awvalid <= 0;
      wvalid <= 0;

      guard = 0;
      while (!bvalid && guard < 100) begin
        @(posedge clk);
        guard = guard + 1;
      end
      check(bvalid && bresp == 2'b00, "AXI write response");

      @(posedge clk);
      bready <= 0;
    end
  endtask

  task axi_read;
    input [11:0] addr;
    output [31:0] data;
    integer guard;
    begin
      @(posedge clk);
      araddr <= addr;
      arvalid <= 1;
      rready <= 1;

      guard = 0;
      while (!arready && guard < 100) begin
        @(posedge clk);
        guard = guard + 1;
      end

      @(posedge clk);
      arvalid <= 0;

      guard = 0;
      while (!rvalid && guard < 100) begin
        @(posedge clk);
        guard = guard + 1;
      end
      data = rdata;
      check(rvalid && rresp == 2'b00, "AXI read response");

      @(posedge clk);
      rready <= 0;
    end
  endtask

  task drive_dataset_burst;
    input integer n_samples;
    integer k;
    begin
      @(posedge clk);
      sample_valid_in <= 1;
      feedback_valid_in <= 1;
      for (k = 0; k < n_samples; k = k + 1) begin
        sample_i_in <= ref_mem[k][31:16];
        sample_q_in <= ref_mem[k][15:0];
        feedback_i_in <= fb_mem[k][31:16];
        feedback_q_in <= fb_mem[k][15:0];
        @(posedge clk);
      end
      @(posedge clk);
      sample_valid_in <= 0;
      feedback_valid_in <= 0;
    end
  endtask

  task pulse_sync;
    begin
      @(posedge clk);
      sync_event <= 1;
      @(posedge clk);
      sync_event <= 0;
    end
  endtask

  task wait_capture_done;
    integer guard;
    begin
      guard = 0;
      while (!dut.capture_done && guard < 100) begin
        @(posedge clk);
        guard = guard + 1;
      end
      check(dut.capture_done, "capture_done asserted after dataset burst");
    end
  endtask

  task report_manual_coverage;
    begin
      $display("\n==== MANUAL COVERAGE: tb_dpd_top_dataset_manual ====");
      $display("dataset_loaded=%0d capture_read=%0d coef_write=%0d switch=%0d retrain=%0d",
               cov_dataset_loaded, cov_capture_read, cov_coef_write, cov_switch, cov_retrain);
      check(cov_dataset_loaded, "coverage: dataset files loaded");
      check(cov_capture_read, "coverage: dataset capture readback");
      check(cov_coef_write, "coverage: coefficient bank write/readback");
      check(cov_switch, "coverage: synchronized switch after dataset capture");
      check(cov_retrain, "coverage: dataset metrics trigger retrain");
    end
  endtask

  initial begin
    reg [31:0] rd;
    reg [31:0] rd_hi;
    reg [31:0] rd_lo;
    integer i;

    errors = 0;
    cov_dataset_loaded = 0;
    cov_capture_read = 0;
    cov_coef_write = 0;
    cov_switch = 0;
    cov_retrain = 0;
/*
    $readmemh("../datasets/synthetic_flow_v1/ref_iq_q15.hex", ref_mem);
    $readmemh("../datasets/synthetic_flow_v1/feedback_iq_q15.hex", fb_mem);
    $readmemh("../datasets/synthetic_flow_v1/expected_capture_hi_delay0.hex", exp_hi);
    $readmemh("../datasets/synthetic_flow_v1/expected_capture_lo_delay0.hex", exp_lo);

    $readmemh("../datasets/dvbt2_64qam45_from_ts/ref_iq_q15.hex", ref_mem);
    $readmemh("../datasets/dvbt2_64qam45_from_ts/feedback_iq_q15.hex", fb_mem);
    $readmemh("../datasets/dvbt2_64qam45_from_ts/expected_capture_hi_delay0.hex", exp_hi);
    $readmemh("../datasets/dvbt2_64qam45_from_ts/expected_capture_lo_delay0.hex", exp_lo);
*/
    $readmemh("../datasets/tv30_atsc3_16k_256qam_fs24m/ref_iq_q15.hex", ref_mem);
    $readmemh("../datasets/tv30_atsc3_16k_256qam_fs24m/feedback_iq_q15.hex", fb_mem);
    $readmemh("../datasets/tv30_atsc3_16k_256qam_fs24m/expected_capture_hi_delay0.hex", exp_hi);
    $readmemh("../datasets/tv30_atsc3_16k_256qam_fs24m/expected_capture_lo_delay0.hex", exp_lo);
    cov_dataset_loaded = 1;

    resetn = 0;
    awaddr = 0;
    awvalid = 0;
    wdata = 0;
    wstrb = 4'hf;
    wvalid = 0;
    bready = 0;
    araddr = 0;
    arvalid = 0;
    rready = 0;
    sample_i_in = 0;
    sample_q_in = 0;
    sample_valid_in = 0;
    feedback_i_in = 0;
    feedback_q_in = 0;
    feedback_valid_in = 0;
    sync_event = 0;
    sample_ready_in = 1;

    repeat (5) @(posedge clk);
    resetn = 1;
    repeat (5) @(posedge clk);

    axi_read(REG_STATUS, rd);
    check(rd[0] == 1'b0 && rd[4] == 1'b0, "reset state bypass and bank A");

    axi_write(REG_DELAY_CTRL, 32'd0);
    axi_write(REG_CAPTURE_CTRL, CAPTURE_N - 1);
    axi_write(REG_CONTROL, CTRL_FORCE_BYPASS | CTRL_CAPTURE);

    drive_dataset_burst(CAPTURE_N + 1);

    wait_capture_done();
    repeat (4) @(posedge clk);
    axi_read(REG_STATUS, rd);
    check(rd[2] == 1'b1 && irq == 1'b1, "dataset capture completes and raises IRQ");
    axi_read(REG_IRQ_STATUS, rd);
    check(rd[0] == 1'b1, "IRQ status records dataset capture_done");

    for (i = 0; i < CAPTURE_N; i = i + 1) begin
      axi_write(REG_CAPTURE_ADDR, i[31:0]);
      axi_read(REG_CAPTURE_HI, rd_hi);
      axi_read(REG_CAPTURE_LO, rd_lo);
      check(rd_hi == exp_hi[i], "dataset capture REF readback");
      check(rd_lo == exp_lo[i], "dataset capture FB readback");
    end
    cov_capture_read = 1;

    axi_write(REG_COEF_ADDR, 32'd0);
    axi_write(REG_COEF_WDATA, 32'h0001_0000);
    axi_write(REG_COEF_CTRL, 32'h2);
    axi_write(REG_COEF_ADDR, 32'd5);
    axi_write(REG_COEF_WDATA, 32'h0002_abcd);
    axi_write(REG_COEF_CTRL, 32'h2);
    repeat (2) @(posedge clk);
    axi_read(REG_COEF_RDATA_B, rd);
    check(rd[CW-1:0] == 18'h2abcd, "coefficient bank B write/readback");
    cov_coef_write = 1;

    axi_write(REG_CONTROL, CTRL_ENABLE | CTRL_COEF_SWITCH);
    repeat (2) @(posedge clk);
    axi_read(REG_STATUS, rd);
    check(rd[3] == 1'b1 && rd[4] == 1'b0, "coefficient switch waits for sync_event");

    pulse_sync();
    repeat (2) @(posedge clk);
    axi_read(REG_STATUS, rd);
    check(rd[0] == 1'b1 && rd[4] == 1'b1, "sync_event activates DPD and switches to bank B");
    cov_switch = 1;

    axi_write(REG_THRESH_ERROR, 32'd0);
    axi_write(REG_THRESH_CLIP, 32'hffff_ffff);
    axi_write(REG_THRESH_DRIFT, 32'd0);

    drive_dataset_burst(8);
    repeat (6) @(posedge clk);
    axi_read(REG_IRQ_STATUS, rd);
    check(rd[2] == 1'b1 && train_request == 1'b1, "dataset metrics trigger retrain request");
    cov_retrain = 1;

    report_manual_coverage();

    if (errors == 0)
      $display("\n[TB PASS] tb_dpd_top_dataset_manual");
    else begin
      $display("\n[TB FAIL] errors=%0d", errors);
      $fatal;
    end

    $finish;
  end
endmodule
