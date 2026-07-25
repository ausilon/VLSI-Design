`timescale 1ns/1ps

module tb_dpd_top_full_system;
  localparam W = 16;
  localparam CW = 18;
  localparam N = 8;

  localparam REG_CONTROL       = 12'h000;
  localparam REG_STATUS        = 12'h004;
  localparam REG_IRQ_STATUS    = 12'h008;
  localparam REG_THRESH_ERROR  = 12'h020;
  localparam REG_THRESH_CLIP   = 12'h024;
  localparam REG_THRESH_DRIFT  = 12'h028;
  localparam REG_COEF_ADDR     = 12'h030;
  localparam REG_COEF_RDATA_A  = 12'h03c;
  localparam REG_COEF_RDATA_B  = 12'h040;
  localparam REG_CAPTURE_CTRL  = 12'h050;
  localparam REG_DELAY_CTRL    = 12'h054;
  localparam REG_TRAIN_CTRL    = 12'h058;
  localparam REG_MAC_ERROR_ACC = 12'h05c;

  localparam CTRL_ENABLE       = 32'h0000_0001;
  localparam CTRL_FORCE_BYPASS = 32'h0000_0002;
  localparam CTRL_CAPTURE      = 32'h0000_0004;
  localparam CTRL_COEF_SWITCH  = 32'h0000_0008;
  localparam CTRL_CLEAR_IRQ    = 32'h0000_0010;
  localparam CTRL_TRAIN_START  = 32'h0000_0020;

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

  reg signed [W-1:0] ref_i [0:N-1];
  reg signed [W-1:0] ref_q [0:N-1];

  integer errors;
  integer k;
  integer expected_error_scale2;
  integer expected_error_scale3;
  integer coef2_real_int;
  integer coef2_imag_int;
  integer coef38_imag_int;
  reg [31:0] rd;
  reg [31:0] metric_error_rd;
  reg [31:0] metric_power_rd;
  reg [31:0] metric_drift_rd;
  reg [31:0] irq_status_rd;

  dpd_top #(
    .SAMPLE_WIDTH(W),
    .COEF_WIDTH(CW),
    .N_COEFS(128),
    .COEF_ADDR_WIDTH(7),
    .CAPTURE_ADDR_WIDTH(10)
  ) dut (
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

  initial clk = 1'b0;
  always #5 clk = ~clk;

  task check;
    input cond;
    input string msg;
    begin
      if (cond !== 1'b1) begin
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
      awvalid <= 1'b1;
      wvalid <= 1'b1;
      bready <= 1'b1;
      guard = 0;
      while (!(awready && wready) && guard < 100) begin
        @(posedge clk);
        guard = guard + 1;
      end
      @(posedge clk);
      awvalid <= 1'b0;
      wvalid <= 1'b0;
      guard = 0;
      while (!bvalid && guard < 100) begin
        @(posedge clk);
        guard = guard + 1;
      end
      if (!(bvalid && bresp == 2'b00)) begin
        errors = errors + 1;
        $display("[FAIL] AXI write response addr=0x%03h data=0x%08h t=%0t", addr, data, $time);
      end
      @(posedge clk);
      bready <= 1'b0;
    end
  endtask

  task axi_read;
    input [11:0] addr;
    output [31:0] data;
    integer guard;
    begin
      @(posedge clk);
      araddr <= addr;
      arvalid <= 1'b1;
      rready <= 1'b1;
      guard = 0;
      while (!arready && guard < 100) begin
        @(posedge clk);
        guard = guard + 1;
      end
      @(posedge clk);
      arvalid <= 1'b0;
      guard = 0;
      while (!rvalid && guard < 100) begin
        @(posedge clk);
        guard = guard + 1;
      end
      data = rdata;
      if (!(rvalid && rresp == 2'b00)) begin
        errors = errors + 1;
        $display("[FAIL] AXI read response addr=0x%03h t=%0t", addr, $time);
      end
      @(posedge clk);
      rready <= 1'b0;
    end
  endtask

  task wait_status_set;
    input integer bit_idx;
    input string msg;
    integer guard;
    begin
      guard = 0;
      rd = 32'd0;
      while (!rd[bit_idx] && guard < 1000000) begin
        axi_read(REG_STATUS, rd);
        guard = guard + 1;
      end
      check(rd[bit_idx], msg);
    end
  endtask

  task wait_status_clear;
    input integer bit_idx;
    input string msg;
    integer guard;
    begin
      guard = 0;
      rd = 32'hffff_ffff;
      while (rd[bit_idx] && guard < 1000000) begin
        axi_read(REG_STATUS, rd);
        guard = guard + 1;
      end
      check(!rd[bit_idx], msg);
    end
  endtask

  task wait_irq_status_set;
    input integer bit_idx;
    input string msg;
    integer guard;
    begin
      guard = 0;
      irq_status_rd = 32'd0;
      while (!irq_status_rd[bit_idx] && guard < 200000) begin
        axi_read(REG_IRQ_STATUS, irq_status_rd);
        guard = guard + 1;
      end
      check(irq_status_rd[bit_idx], msg);
    end
  endtask

  task wait_train_cycle_done;
    input string phase_name;
    begin
      wait_status_set(8, {phase_name, " train_busy asserted"});
      wait_status_clear(8, {phase_name, " train_busy deasserted"});
      wait_status_set(9, {phase_name, " train_done asserted"});
      axi_read(REG_STATUS, rd);
      check(rd[10] == 1'b0, {phase_name, " train_error clear"});
      check(rd[11] == 1'b1, {phase_name, " coef_ready asserted"});
    end
  endtask

  task wait_sample_ready;
    integer guard;
    begin
      guard = 0;
      while (!sample_ready_out && guard < 1000) begin
        @(posedge clk);
        guard = guard + 1;
      end
      check(sample_ready_out, "fast path ready");
    end
  endtask

  task pulse_sync_event;
    begin
      @(posedge clk);
      sync_event <= 1'b1;
      @(posedge clk);
      sync_event <= 1'b0;
    end
  endtask

  task init_dataset;
    begin
      ref_i[0] = 16'sd1000;   ref_q[0] = -16'sd500;
      ref_i[1] = -16'sd1500;  ref_q[1] = 16'sd700;
      ref_i[2] = 16'sd2200;   ref_q[2] = 16'sd1100;
      ref_i[3] = -16'sd800;   ref_q[3] = -16'sd1200;
      ref_i[4] = 16'sd3200;   ref_q[4] = -16'sd900;
      ref_i[5] = -16'sd2600;  ref_q[5] = 16'sd1700;
      ref_i[6] = 16'sd1800;   ref_q[6] = 16'sd2400;
      ref_i[7] = -16'sd1200;  ref_q[7] = -16'sd2100;

      expected_error_scale2 = 0;
      expected_error_scale3 = 0;
      for (k = 0; k < N; k = k + 1) begin
        expected_error_scale2 = expected_error_scale2 +
          (ref_i[k] < 0 ? -ref_i[k] : ref_i[k]) +
          (ref_q[k] < 0 ? -ref_q[k] : ref_q[k]);
        expected_error_scale3 = expected_error_scale3 +
          2 * ((ref_i[k] < 0 ? -ref_i[k] : ref_i[k]) +
               (ref_q[k] < 0 ? -ref_q[k] : ref_q[k]));
      end
    end
  endtask

  task drive_aligned_capture;
    input integer fb_scale;
    begin
      wait_sample_ready();

      // delay_align with delay_cfg=0 is registered and capture samples the
      // previous aligned output. Prime two feedback cycles before REF[0].
      @(negedge clk);
      sample_i_in <= 16'sd0;
      sample_q_in <= 16'sd0;
      sample_valid_in <= 1'b1;
      feedback_valid_in <= 1'b1;
      feedback_i_in <= ref_i[0] * fb_scale;
      feedback_q_in <= ref_q[0] * fb_scale;
      @(posedge clk);

      @(negedge clk);
      sample_i_in <= 16'sd0;
      sample_q_in <= 16'sd0;
      sample_valid_in <= 1'b1;
      feedback_valid_in <= 1'b1;
      feedback_i_in <= ref_i[1] * fb_scale;
      feedback_q_in <= ref_q[1] * fb_scale;
      @(posedge clk);

      for (k = 0; k < N; k = k + 1) begin
        @(negedge clk);
        sample_i_in <= ref_i[k];
        sample_q_in <= ref_q[k];
        sample_valid_in <= 1'b1;
        feedback_valid_in <= 1'b1;
        if (k < N-2) begin
          feedback_i_in <= ref_i[k+2] * fb_scale;
          feedback_q_in <= ref_q[k+2] * fb_scale;
        end else begin
          feedback_i_in <= 16'sd0;
          feedback_q_in <= 16'sd0;
        end
        @(posedge clk);
      end

      @(negedge clk);
      sample_valid_in <= 1'b0;
      feedback_valid_in <= 1'b0;
    end
  endtask

  task drive_metric_stream;
    input integer fb_scale;
    input integer n_samples;
    integer n;
    integer idx;
    begin
      wait_sample_ready();
      for (n = 0; n < n_samples; n = n + 1) begin
        idx = n % N;
        @(negedge clk);
        if (sample_ready_out) begin
          sample_i_in <= ref_i[idx];
          sample_q_in <= ref_q[idx];
          feedback_i_in <= ref_i[idx] * fb_scale;
          feedback_q_in <= ref_q[idx] * fb_scale;
          sample_valid_in <= 1'b1;
          feedback_valid_in <= 1'b1;
        end
        @(posedge clk);
      end

      @(negedge clk);
      sample_valid_in <= 1'b0;
      feedback_valid_in <= 1'b0;
    end
  endtask

  task read_coef_bank_a;
    input integer addr;
    output [31:0] data;
    begin
      axi_write(REG_COEF_ADDR, addr[31:0]);
      axi_read(REG_COEF_RDATA_A, data);
    end
  endtask

  task read_coef_bank_b;
    input integer addr;
    output [31:0] data;
    begin
      axi_write(REG_COEF_ADDR, addr[31:0]);
      axi_read(REG_COEF_RDATA_B, data);
    end
  endtask

  task check_trained_bank_b;
    begin
      read_coef_bank_b(4, rd);
      coef2_real_int = $signed(rd[CW-1:0]);
      check(!$isunknown(rd[CW-1:0]) && coef2_real_int > 0,
            "first training wrote finite positive bank-B Re{coef2}");
      read_coef_bank_b(5, rd);
      coef2_imag_int = $signed(rd[CW-1:0]);
      check(!$isunknown(rd[CW-1:0]) && coef2_imag_int >= -512 && coef2_imag_int <= 512,
            "first training wrote small finite bank-B Im{coef2}");
      read_coef_bank_b(77, rd);
      coef38_imag_int = $signed(rd[CW-1:0]);
      check(!$isunknown(rd[CW-1:0]), "first training wrote finite bank-B final coefficient word");
      $display("[TRAIN1] bank=B coef2_re=%0d coef2_im=%0d coef38_im=%0d",
               coef2_real_int, coef2_imag_int, coef38_imag_int);
    end
  endtask

  task check_trained_bank_a;
    begin
      read_coef_bank_a(4, rd);
      coef2_real_int = $signed(rd[CW-1:0]);
      check(!$isunknown(rd[CW-1:0]) && coef2_real_int > 0,
            "retraining wrote finite positive bank-A Re{coef2}");
      read_coef_bank_a(5, rd);
      coef2_imag_int = $signed(rd[CW-1:0]);
      check(!$isunknown(rd[CW-1:0]) && coef2_imag_int >= -512 && coef2_imag_int <= 512,
            "retraining wrote small finite bank-A Im{coef2}");
      read_coef_bank_a(77, rd);
      coef38_imag_int = $signed(rd[CW-1:0]);
      check(!$isunknown(rd[CW-1:0]), "retraining wrote finite bank-A final coefficient word");
      $display("[TRAIN2] bank=A coef2_re=%0d coef2_im=%0d coef38_im=%0d",
               coef2_real_int, coef2_imag_int, coef38_imag_int);
    end
  endtask

  initial begin
    errors = 0;
    init_dataset();

    resetn = 1'b0;
    awaddr = 12'd0;
    awvalid = 1'b0;
    wdata = 32'd0;
    wstrb = 4'hf;
    wvalid = 1'b0;
    bready = 1'b0;
    araddr = 12'd0;
    arvalid = 1'b0;
    rready = 1'b0;
    sample_i_in = '0;
    sample_q_in = '0;
    sample_valid_in = 1'b0;
    feedback_i_in = '0;
    feedback_q_in = '0;
    feedback_valid_in = 1'b0;
    sync_event = 1'b0;
    sample_ready_in = 1'b1;

    repeat (8) @(posedge clk);
    resetn = 1'b1;
    repeat (5) @(posedge clk);

    $display("[PHASE] boot in bypass and configure capture/train t=%0t", $time);
    axi_read(REG_STATUS, rd);
    check(rd[0] == 1'b0, "reset starts with DPD inactive/bypass");
    axi_write(REG_DELAY_CTRL, 32'd0);
    axi_write(REG_CAPTURE_CTRL, N-1);
    axi_write(REG_TRAIN_CTRL, N-1);
    axi_write(REG_THRESH_ERROR, 32'h7fff_ffff);
    axi_write(REG_THRESH_CLIP, 32'h7fff_ffff);
    axi_write(REG_THRESH_DRIFT, 32'h7fff_ffff);

    $display("[PHASE] initial capture while fast path is bypassed t=%0t", $time);
    axi_write(REG_CONTROL, CTRL_FORCE_BYPASS | CTRL_CAPTURE);
    wait_status_set(1, "initial capture_busy asserted");
    drive_aligned_capture(2);
    wait_status_set(2, "initial capture_done asserted");
    wait_irq_status_set(0, "capture_done IRQ status bit latched");

    $display("[PHASE] first internal NLMS training t=%0t", $time);
    axi_write(REG_CONTROL, CTRL_FORCE_BYPASS | CTRL_TRAIN_START);
    wait_train_cycle_done("initial");
    axi_read(REG_MAC_ERROR_ACC, rd);
    check(rd >= expected_error_scale2[31:0] * 10 &&
          rd <= expected_error_scale2[31:0] * 20,
          "initial MAC error accumulator tracks 10..20 epochs");
    check_trained_bank_b();

    $display("[PHASE] switch to bank B and enable DPD t=%0t", $time);
    axi_write(REG_CONTROL, CTRL_COEF_SWITCH);
    wait_status_set(12, "coefficient switch pending before sync_event");
    axi_write(REG_CONTROL, CTRL_ENABLE);
    pulse_sync_event();
    repeat (5) @(posedge clk);
    axi_read(REG_STATUS, rd);
    check(rd[0] == 1'b1, "DPD active after first sync_event");
    check(rd[4] == 1'b1, "bank B active after first sync_event");
    wait_irq_status_set(1, "coefficient-switch IRQ status bit latched");

    $display("[PHASE] metrics trigger retrain request t=%0t", $time);
    axi_write(REG_CONTROL, CTRL_ENABLE | CTRL_CLEAR_IRQ);
    axi_write(REG_THRESH_ERROR, 32'd1);
    axi_write(REG_THRESH_DRIFT, 32'd1);
    drive_metric_stream(3, 48);
    repeat (80) @(posedge clk);
    axi_read(12'h010, metric_power_rd);
    axi_read(12'h014, metric_error_rd);
    axi_read(12'h01c, metric_drift_rd);
    axi_read(REG_IRQ_STATUS, irq_status_rd);
    check(metric_power_rd > 0, "metric_power updated with DPD active");
    check(metric_error_rd > 1, "metric_error crossed retrain threshold");
    check(metric_drift_rd > 1, "metric_drift updated with DPD active");
    check(train_request && irq_status_rd[2] && irq, "metrics latched retrain_request IRQ");
    $display("[METRIC] power=%0d error=%0d drift=%0d irq_status=0x%08h train_request=%0b irq=%0b",
             metric_power_rd, metric_error_rd, metric_drift_rd, irq_status_rd, train_request, irq);

    $display("[PHASE] retrain from new capture while DPD remains enabled t=%0t", $time);
    axi_write(REG_CONTROL, CTRL_ENABLE | CTRL_CLEAR_IRQ);
    axi_write(REG_THRESH_ERROR, 32'h7fff_ffff);
    axi_write(REG_THRESH_DRIFT, 32'h7fff_ffff);
    axi_write(REG_CONTROL, CTRL_ENABLE | CTRL_CAPTURE);
    wait_status_set(1, "retrain capture_busy asserted");
    drive_aligned_capture(3);
    wait_status_set(2, "retrain capture_done asserted");

    axi_write(REG_CONTROL, CTRL_ENABLE | CTRL_TRAIN_START);
    wait_train_cycle_done("retrain");
    axi_read(REG_MAC_ERROR_ACC, rd);
    check(rd >= expected_error_scale3[31:0] * 10 &&
          rd <= expected_error_scale3[31:0] * 20,
          "retrain MAC error accumulator tracks new PA scale");
    check_trained_bank_a();

    $display("[PHASE] switch back to bank A after retrain t=%0t", $time);
    axi_write(REG_CONTROL, CTRL_ENABLE | CTRL_COEF_SWITCH);
    wait_status_set(12, "retrain coefficient switch pending before sync_event");
    pulse_sync_event();
    repeat (5) @(posedge clk);
    axi_read(REG_STATUS, rd);
    check(rd[0] == 1'b1, "DPD remains active after retrain switch");
    check(rd[4] == 1'b0, "bank A active after retrain sync_event");

    drive_metric_stream(3, 24);
    repeat (40) @(posedge clk);
    check(sample_valid_out !== 1'bx, "full-system output valid signal remains known");
    check(!$isunknown(sample_i_out) && !$isunknown(sample_q_out),
          "full-system output samples remain finite after retrain");

    if (errors == 0) begin
      $display("\n[TB PASS] tb_dpd_top_full_system");
    end else begin
      $display("\n[TB FAIL] errors=%0d", errors);
      $fatal;
    end
    repeat (200) @(posedge clk);
    $finish;
  end
endmodule
