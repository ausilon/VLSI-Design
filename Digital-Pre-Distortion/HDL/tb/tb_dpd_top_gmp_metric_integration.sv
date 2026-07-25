`timescale 1ns/1ps

module tb_dpd_top_gmp_metric_integration;
  localparam W = 16;
  localparam CW = 18;
  localparam N_COEFS = 128;
  localparam N_COEF_WORDS = 78;
  localparam N_INPUTS = 66;
  localparam N_EXPECTED = 64;

  localparam REG_CONTROL       = 12'h000;
  localparam REG_STATUS        = 12'h004;
  localparam REG_IRQ_STATUS    = 12'h008;
  localparam REG_IRQ_MASK      = 12'h00c;
  localparam REG_METRIC_POWER  = 12'h010;
  localparam REG_METRIC_ERROR  = 12'h014;
  localparam REG_METRIC_CLIP   = 12'h018;
  localparam REG_METRIC_DRIFT  = 12'h01c;
  localparam REG_THRESH_ERROR  = 12'h020;
  localparam REG_THRESH_CLIP   = 12'h024;
  localparam REG_THRESH_DRIFT  = 12'h028;
  localparam REG_COEF_ADDR     = 12'h030;
  localparam REG_COEF_WDATA    = 12'h034;
  localparam REG_COEF_CTRL     = 12'h038;
  localparam REG_COEF_RDATA_A  = 12'h03c;
  localparam REG_DELAY_CTRL    = 12'h054;

  localparam CTRL_ENABLE       = 32'h0000_0001;
  localparam COEF_WRITE_A      = 32'h0000_0001;

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

  reg signed [CW-1:0] coef_mem [0:N_COEFS-1];
  reg [31:0] sample_mem [0:N_INPUTS-1];
  reg [31:0] expected_mem [0:N_EXPECTED-1];

  string coef_path;
  string sample_path;
  string expected_path;

  integer errors;
  integer sample_idx;
  integer expected_idx;
  integer guard;
  integer file_handle;
  integer print_every;
  integer denom;
  integer drift_bp;
  integer err_bp;

  reg [31:0] rd_tmp;
  reg [31:0] metric_power_rd;
  reg [31:0] metric_error_rd;
  reg [31:0] metric_clip_rd;
  reg [31:0] metric_drift_rd;
  reg [31:0] irq_status_rd;
  reg signed [W-1:0] exp_i;
  reg signed [W-1:0] exp_q;

  dpd_top #(
    .SAMPLE_WIDTH(W),
    .COEF_WIDTH(CW),
    .N_COEFS(N_COEFS),
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
      if (!cond) begin
        errors = errors + 1;
        $display("[FAIL] %0s t=%0t", msg, $time);
      end else begin
        $display("[PASS] %0s", msg);
      end
    end
  endtask

  task require_readable_file;
    input string path;
    begin
      file_handle = $fopen(path, "r");
      if (file_handle == 0) begin
        $display("[FATAL] Cannot open required file: %s", path);
        $display("[FATAL] Run from /home/Ausilon/Desktop/dpd_v1/dpd_soc_min or pass absolute +COEF_HEX/+SAMPLES_HEX/+EXPECTED_HEX paths.");
        $fatal;
      end
      $fclose(file_handle);
    end
  endtask

  task axi_write;
    input [11:0] addr;
    input [31:0] data;
    integer axi_guard;
    begin
      @(posedge clk);
      awaddr <= addr;
      wdata <= data;
      wstrb <= 4'hf;
      awvalid <= 1'b1;
      wvalid <= 1'b1;
      bready <= 1'b1;

      axi_guard = 0;
      while (!(awready && wready) && axi_guard < 100) begin
        @(posedge clk);
        axi_guard = axi_guard + 1;
      end

      @(posedge clk);
      awvalid <= 1'b0;
      wvalid <= 1'b0;

      axi_guard = 0;
      while (!bvalid && axi_guard < 100) begin
        @(posedge clk);
        axi_guard = axi_guard + 1;
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
    integer axi_guard;
    begin
      @(posedge clk);
      araddr <= addr;
      arvalid <= 1'b1;
      rready <= 1'b1;

      axi_guard = 0;
      while (!arready && axi_guard < 100) begin
        @(posedge clk);
        axi_guard = axi_guard + 1;
      end

      @(posedge clk);
      arvalid <= 1'b0;

      axi_guard = 0;
      while (!rvalid && axi_guard < 100) begin
        @(posedge clk);
        axi_guard = axi_guard + 1;
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

  task write_coef_bank_a;
    integer k;
    begin
      for (k = 0; k < N_COEF_WORDS; k = k + 1) begin
        axi_write(REG_COEF_ADDR, k[31:0]);
        axi_write(REG_COEF_WDATA, {{(32-CW){coef_mem[k][CW-1]}}, coef_mem[k]});
        axi_write(REG_COEF_CTRL, COEF_WRITE_A);
      end
      $display("[INFO] wrote %0d OpenDPD coefficient words into bank A through AXI-Lite", N_COEF_WORDS);

      axi_write(REG_COEF_ADDR, 32'd0);
      axi_read(REG_COEF_RDATA_A, rd_tmp);
      check(rd_tmp[CW-1:0] == coef_mem[0], "coefficient bank A word 0 readable through AXI");
      axi_write(REG_COEF_ADDR, 32'd1);
      axi_read(REG_COEF_RDATA_A, rd_tmp);
      check(rd_tmp[CW-1:0] == coef_mem[1], "coefficient bank A word 1 readable through AXI");
      axi_write(REG_COEF_ADDR, 32'd4);
      axi_read(REG_COEF_RDATA_A, rd_tmp);
      check(rd_tmp[CW-1:0] == coef_mem[4], "coefficient bank A word 4 readable through AXI");
    end
  endtask

  task print_metric_summary;
    integer err_whole;
    integer err_frac;
    integer drift_whole;
    integer drift_frac;
    begin
      denom = (metric_power_rd == 0) ? 1 : metric_power_rd;
      err_bp = (metric_error_rd * 10000) / denom;
      drift_bp = (metric_drift_rd * 10000) / denom;
      err_whole = err_bp / 100;
      err_frac = err_bp % 100;
      drift_whole = drift_bp / 100;
      drift_frac = drift_bp % 100;

      $display("[METRIC] AXI metric_power_l1_ewma=%0d metric_error_ref_fb_l1_ewma=%0d err_rel=%0d.%02d%% metric_drift_dpd_ref_l1_ewma=%0d drift_rel=%0d.%02d%% clipping_count=%0d irq_status=0x%08h irq=%0d train_request=%0d",
               metric_power_rd,
               metric_error_rd,
               err_whole,
               err_frac,
               metric_drift_rd,
               drift_whole,
               drift_frac,
               metric_clip_rd,
               irq_status_rd,
               irq,
               train_request);
    end
  endtask

  initial begin
    if (!$value$plusargs("COEF_HEX=%s", coef_path))
      coef_path = "/home/Ausilon/Desktop/dpd_v1/dpd_soc_min/datasets/opendpd_coeffs/coef_bank_openDPD.hex";
    if (!$value$plusargs("SAMPLES_HEX=%s", sample_path))
      sample_path = "/home/Ausilon/Desktop/dpd_v1/dpd_soc_min/datasets/opendpd_coeffs/gmp_opendpd_full_samples_iq_q15.hex";
    if (!$value$plusargs("EXPECTED_HEX=%s", expected_path))
      expected_path = "/home/Ausilon/Desktop/dpd_v1/dpd_soc_min/datasets/opendpd_coeffs/gmp_opendpd_full_expected_iq_q15.hex";
    if (!$value$plusargs("PRINT_EVERY=%d", print_every))
      print_every = 8;
    if (print_every <= 0)
      print_every = 8;

    $display("Loading coefficients: %s", coef_path);
    $display("Loading samples:      %s", sample_path);
    $display("Loading expected:     %s", expected_path);
    require_readable_file(coef_path);
    require_readable_file(sample_path);
    require_readable_file(expected_path);
    $readmemh(coef_path, coef_mem);
    $readmemh(sample_path, sample_mem);
    $readmemh(expected_path, expected_mem);

    errors = 0;
    sample_idx = 0;
    expected_idx = 0;
    guard = 0;

    resetn = 1'b0;
    awaddr = 12'd0;
    awvalid = 1'b0;
    wdata = 32'd0;
    wstrb = 4'd0;
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

    check(coef_mem[0] === 18'h005ED, "OpenDPD coefficient word 0 loaded from file");
    check(coef_mem[1] === 18'h00000, "OpenDPD coefficient word 1 loaded from file");
    check(coef_mem[4] === 18'h0AC4E, "OpenDPD coefficient word 4 loaded from file");

    axi_write(REG_IRQ_MASK, 32'h0000_0007);
    axi_write(REG_THRESH_ERROR, 32'hffff_ffff);
    axi_write(REG_THRESH_CLIP, 32'hffff_ffff);
    axi_write(REG_THRESH_DRIFT, 32'hffff_ffff);
    axi_write(REG_DELAY_CTRL, 32'd0);
    write_coef_bank_a();

    axi_write(REG_CONTROL, CTRL_ENABLE);

    @(posedge clk);
    sync_event <= 1'b1;
    @(posedge clk);
    sync_event <= 1'b0;

    guard = 0;
    while ((!dpd_active || !sample_ready_out) && guard < 300) begin
      @(posedge clk);
      guard = guard + 1;
    end
    check(dpd_active, "dpd_top active after enable and sync_event");
    check(sample_ready_out, "dpd_top/GMP ready after coefficient reload");

    guard = 0;
    while (expected_idx < N_EXPECTED && guard < 5000) begin
      @(negedge clk);
      if (sample_idx < N_INPUTS && sample_ready_out) begin
        sample_i_in <= sample_mem[sample_idx][31:16];
        sample_q_in <= sample_mem[sample_idx][15:0];
        feedback_i_in <= sample_mem[sample_idx][31:16];
        feedback_q_in <= sample_mem[sample_idx][15:0];
        sample_valid_in <= 1'b1;
        feedback_valid_in <= 1'b1;
        sample_idx = sample_idx + 1;
      end else begin
        sample_valid_in <= 1'b0;
        feedback_valid_in <= 1'b0;
      end

      @(posedge clk);
      #1;
      if (sample_valid_out) begin
        exp_i = expected_mem[expected_idx][31:16];
        exp_q = expected_mem[expected_idx][15:0];
        if ($isunknown(sample_i_out) || $isunknown(sample_q_out) ||
            $isunknown(exp_i) || $isunknown(exp_q)) begin
          errors = errors + 1;
          $display("[FAIL] top output sample %0d has unknown value expected=(%0d,%0d) got=(%0d,%0d)",
                   expected_idx, exp_i, exp_q, sample_i_out, sample_q_out);
        end else if (sample_i_out !== exp_i || sample_q_out !== exp_q) begin
          errors = errors + 1;
          $display("[FAIL] top output sample %0d expected=(%0d,%0d) got=(%0d,%0d)",
                   expected_idx, exp_i, exp_q, sample_i_out, sample_q_out);
        end else if ((expected_idx % print_every) == 0 || expected_idx == N_EXPECTED-1) begin
          $display("[PASS] top output sample %0d I=%0d Q=%0d", expected_idx, sample_i_out, sample_q_out);
        end
        expected_idx = expected_idx + 1;
      end
      guard = guard + 1;
    end

    @(negedge clk);
    sample_valid_in <= 1'b0;
    feedback_valid_in <= 1'b0;
    repeat (8) @(posedge clk);

    check(sample_idx == N_INPUTS, "all input samples accepted by dpd_top");
    check(expected_idx == N_EXPECTED, "all expected GMP outputs produced by dpd_top");

    axi_read(REG_STATUS, rd_tmp);
    check(rd_tmp[0] == 1'b1, "STATUS.dpd_active is set");

    axi_read(REG_METRIC_POWER, metric_power_rd);
    axi_read(REG_METRIC_ERROR, metric_error_rd);
    axi_read(REG_METRIC_CLIP, metric_clip_rd);
    axi_read(REG_METRIC_DRIFT, metric_drift_rd);
    axi_read(REG_IRQ_STATUS, irq_status_rd);
    print_metric_summary();

    check(metric_power_rd != 32'd0, "metric_power updated through integrated metric_engine");
    check(metric_drift_rd != 32'd0, "metric_drift updated because DPD output differs from reference");

    if (errors == 0) begin
      $display("\n[TB PASS] tb_dpd_top_gmp_metric_integration");
    end else begin
      $display("\n[TB FAIL] errors=%0d", errors);
      $fatal;
    end
    $finish;
  end
endmodule
