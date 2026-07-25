`timescale 1ns/1ps

module tb_dpd_top_internal_train_linear;
  localparam W = 16;
  localparam CW = 18;
  localparam N = 4;

  localparam REG_CONTROL       = 12'h000;
  localparam REG_STATUS        = 12'h004;
  localparam REG_COEF_ADDR     = 12'h030;
  localparam REG_COEF_RDATA_B  = 12'h040;
  localparam REG_CAPTURE_CTRL  = 12'h050;
  localparam REG_DELAY_CTRL    = 12'h054;
  localparam REG_TRAIN_CTRL    = 12'h058;
  localparam REG_MAC_ERROR_ACC = 12'h05c;

  localparam CTRL_FORCE_BYPASS = 32'h0000_0002;
  localparam CTRL_CAPTURE      = 32'h0000_0004;
  localparam CTRL_COEF_SWITCH  = 32'h0000_0008;
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
  integer expected_error;
  integer k;
  integer coef2_real_int;
  integer coef2_imag_int;
  integer coef38_imag_int;
  reg [31:0] rd;

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
        $display("[FAIL] AXI write response addr=0x%03h data=0x%08h", addr, data);
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
        $display("[FAIL] AXI read response addr=0x%03h", addr);
      end
      @(posedge clk);
      rready <= 1'b0;
    end
  endtask

  task wait_status_bit;
    input integer bit_idx;
    input string msg;
    integer guard;
    begin
      guard = 0;
      rd = 32'd0;
      while (!rd[bit_idx] && guard < 250000) begin
        axi_read(REG_STATUS, rd);
        guard = guard + 1;
      end
      check(rd[bit_idx], msg);
    end
  endtask

  task drive_aligned_capture;
    begin
      // delay_align with delay_cfg=0 is registered and capture samples the
      // previous aligned output. Prime two feedback cycles before REF[0].
      @(negedge clk);
      sample_i_in <= 16'sd0;
      sample_q_in <= 16'sd0;
      sample_valid_in <= 1'b1;
      feedback_valid_in <= 1'b1;
      feedback_i_in <= ref_i[0] <<< 1;
      feedback_q_in <= ref_q[0] <<< 1;
      @(posedge clk);

      @(negedge clk);
      sample_i_in <= 16'sd0;
      sample_q_in <= 16'sd0;
      sample_valid_in <= 1'b1;
      feedback_valid_in <= 1'b1;
      feedback_i_in <= ref_i[1] <<< 1;
      feedback_q_in <= ref_q[1] <<< 1;
      @(posedge clk);

      for (k = 0; k < N; k = k + 1) begin
        @(negedge clk);
        sample_i_in <= ref_i[k];
        sample_q_in <= ref_q[k];
        sample_valid_in <= 1'b1;
        feedback_valid_in <= 1'b1;
        if (k < N-2) begin
          feedback_i_in <= ref_i[k+2] <<< 1;
          feedback_q_in <= ref_q[k+2] <<< 1;
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

  task read_coef_b;
    input integer addr;
    output [31:0] data;
    begin
      axi_write(REG_COEF_ADDR, addr[31:0]);
      axi_read(REG_COEF_RDATA_B, data);
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

  task wait_sample_ready;
    integer guard;
    begin
      guard = 0;
      while (!sample_ready_out && guard < 400) begin
        @(posedge clk);
        guard = guard + 1;
      end
      check(sample_ready_out, "GMP ready after coefficient-bank switch/reload");
    end
  endtask

  task drive_visible_sample;
    input signed [W-1:0] ii;
    input signed [W-1:0] qq;
    begin
      wait_sample_ready();
      @(negedge clk);
      sample_i_in <= ii;
      sample_q_in <= qq;
      feedback_i_in <= ii <<< 1;
      feedback_q_in <= qq <<< 1;
      sample_valid_in <= 1'b1;
      feedback_valid_in <= 1'b1;
      @(posedge clk);
      @(negedge clk);
      sample_valid_in <= 1'b0;
      feedback_valid_in <= 1'b0;
    end
  endtask

  task wait_output_valid;
    integer guard;
    begin
      guard = 0;
      while (!sample_valid_out && guard < 200) begin
        @(posedge clk);
        guard = guard + 1;
      end
      check(sample_valid_out, "DPD active output valid after trained coefficient switch");
    end
  endtask

  task drive_trained_dpd_burst_and_check;
    input signed [W-1:0] ii;
    input signed [W-1:0] qq;
    integer n;
    integer hit_valid;
    integer guard;
    begin
      hit_valid = 0;
      wait_sample_ready();
      for (n = 0; n < 10; n = n + 1) begin
        @(negedge clk);
        if (sample_ready_out) begin
          sample_i_in <= ii;
          sample_q_in <= qq;
          feedback_i_in <= ii <<< 1;
          feedback_q_in <= qq <<< 1;
          sample_valid_in <= 1'b1;
          feedback_valid_in <= 1'b1;
        end
        @(posedge clk);
        #1;
        if (sample_valid_out && !$isunknown(sample_i_out) && !$isunknown(sample_q_out))
          hit_valid = 1;
      end

      @(negedge clk);
      sample_valid_in <= 1'b0;
      feedback_valid_in <= 1'b0;

      guard = 0;
      while (!hit_valid && guard < 30) begin
        @(posedge clk);
        #1;
        if (sample_valid_out && !$isunknown(sample_i_out) && !$isunknown(sample_q_out))
          hit_valid = 1;
        guard = guard + 1;
      end
      check(hit_valid, "trained 39-term DPD produces finite output after GMP lookahead/pipeline");
    end
  endtask

  initial begin
    errors = 0;
    expected_error = 0;

    ref_i[0] = 16'sd1000;  ref_q[0] = -16'sd500;
    ref_i[1] = -16'sd1500; ref_q[1] = 16'sd700;
    ref_i[2] = 16'sd2200;  ref_q[2] = 16'sd1100;
    ref_i[3] = -16'sd800;  ref_q[3] = -16'sd1200;
    expected_error = 1000 + 500 + 1500 + 700 + 2200 + 1100 + 800 + 1200;

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

    repeat (6) @(posedge clk);
    resetn = 1'b1;
    repeat (4) @(posedge clk);

    axi_write(REG_DELAY_CTRL, 32'd0);
    axi_write(REG_CAPTURE_CTRL, N-1);
    axi_write(REG_TRAIN_CTRL, N-1);
    axi_write(REG_CONTROL, CTRL_FORCE_BYPASS | CTRL_CAPTURE);
    drive_aligned_capture();

    wait_status_bit(2, "capture_done set before internal training");

    axi_write(REG_CONTROL, CTRL_FORCE_BYPASS | CTRL_TRAIN_START);
    wait_status_bit(9, "train_done set after MACcore internal training");
    axi_read(REG_STATUS, rd);
    check(rd[10] == 1'b0, "STATUS.train_error remains clear");
    check(rd[11] == 1'b1, "STATUS.coef_ready asserted");

    read_coef_b(4, rd);
    coef2_real_int = $signed(rd[CW-1:0]);
    check(!$isunknown(rd[CW-1:0]) && coef2_real_int > 0 && coef2_real_int <= 32768,
          "bank B finite positive Re{coef2} central linear term from NLMS training");
    read_coef_b(5, rd);
    coef2_imag_int = $signed(rd[CW-1:0]);
    check(!$isunknown(rd[CW-1:0]) && coef2_imag_int >= -512 && coef2_imag_int <= 512,
          "bank B small finite Im{coef2} central linear term from NLMS training");
    read_coef_b(77, rd);
    coef38_imag_int = $signed(rd[CW-1:0]);
    check(!$isunknown(rd[CW-1:0]) && rd[CW-1:0] !== 18'h3ffff,
          "bank B last GMP coefficient word was written");

    axi_read(REG_MAC_ERROR_ACC, rd);
    check(rd >= expected_error[31:0] * 10 &&
          rd <= expected_error[31:0] * 20,
          "MAC error accumulator visible through AXI for 10..20 NLMS epochs");

    $display("[TRAIN_TOP] coef2_real_q216=%0d coef2_imag_q216=%0d coef38_imag_q216=%0d mac_error_acc=%0d active_bank=%0d",
             coef2_real_int, coef2_imag_int, coef38_imag_int, rd, dut.active_bank);

    $display("[PHASE] request coefficient switch to trained bank B t=%0t", $time);
    axi_write(REG_CONTROL, CTRL_COEF_SWITCH);
    axi_read(REG_STATUS, rd);
    check(rd[12] == 1'b1 && rd[4] == 1'b0 && dpd_active == 1'b0,
          "switch pending while still bypass/active bank A");

    $display("[PHASE] sync_event switches bank and enables DPD t=%0t", $time);
    axi_write(REG_CONTROL, 32'h0000_0001);
    pulse_sync_event();
    repeat (3) @(posedge clk);
    axi_read(REG_STATUS, rd);
    check(rd[4] == 1'b1, "active_bank switched to bank B");
    check(dpd_active == 1'b1, "dpd_active toggled high after sync_event");

    $display("[PHASE] drive sample through trained 39-term DPD t=%0t", $time);
    drive_trained_dpd_burst_and_check(16'sd4000, -16'sd2000);

    $display("[PHASE] force bypass again t=%0t", $time);
    axi_write(REG_CONTROL, CTRL_FORCE_BYPASS);
    pulse_sync_event();
    repeat (2) @(posedge clk);
    check(dpd_active == 1'b0, "dpd_active toggled low after force_bypass sync_event");
    drive_visible_sample(16'sd1234, -16'sd567);
    wait_output_valid();
    check(sample_i_out == 16'sd1234 && sample_q_out == -16'sd567,
          "bypass output equals input after DPD disable");

    if (errors == 0) begin
      $display("\n[TB PASS] tb_dpd_top_internal_train_linear");
    end else begin
      $display("\n[TB FAIL] errors=%0d", errors);
      $fatal;
    end
    repeat (200) @(posedge clk);
    $finish;
  end
endmodule
