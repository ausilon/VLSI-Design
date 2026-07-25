`timescale 1ns/1ps

module tb_metric_engine;
  localparam W = 16;
  localparam CW = 18;
  localparam N_COEFS = 128;
  localparam N_INPUTS = 66;
  localparam N_EXPECTED = 64;

  reg clk;
  reg resetn;
  reg clear;

  reg gmp_enable;
  reg signed [W-1:0] gmp_i_in;
  reg signed [W-1:0] gmp_q_in;
  reg gmp_in_valid;
  reg gmp_out_ready;
  wire gmp_in_ready;
  wire signed [W-1:0] gmp_i_out;
  wire signed [W-1:0] gmp_q_out;
  wire gmp_out_valid;
  wire [6:0] gmp_coef_addr;
  wire gmp_busy;

  reg signed [W-1:0] metric_ref_i;
  reg signed [W-1:0] metric_ref_q;
  reg signed [W-1:0] metric_fb_i;
  reg signed [W-1:0] metric_fb_q;
  reg metric_sample_valid;
  reg signed [W-1:0] metric_dpd_i;
  reg signed [W-1:0] metric_dpd_q;
  reg metric_dpd_valid;

  reg [31:0] threshold_error;
  reg [31:0] threshold_clip;
  reg [31:0] threshold_drift;
  wire [31:0] metric_power;
  wire [31:0] metric_error;
  wire [31:0] metric_clipping;
  wire [31:0] metric_drift;
  wire metrics_valid;
  wire retrain_request;

  reg signed [CW-1:0] coef_mem [0:N_COEFS-1];
  reg [31:0] sample_mem [0:N_INPUTS-1];
  reg [31:0] expected_mem [0:N_EXPECTED-1];
  reg signed [CW-1:0] coef_data;

  reg signed [W-1:0] hist_ref_i [0:N_EXPECTED-1];
  reg signed [W-1:0] hist_ref_q [0:N_EXPECTED-1];
  reg signed [W-1:0] hist_dpd_i [0:N_EXPECTED-1];
  reg signed [W-1:0] hist_dpd_q [0:N_EXPECTED-1];
  reg signed [W-1:0] hist_fb_i [0:N_EXPECTED-1];
  reg signed [W-1:0] hist_fb_q [0:N_EXPECTED-1];
  reg hist_dpd_enable [0:N_EXPECTED-1];

  string coef_path;
  string sample_path;
  string expected_path;
  string fb_mode;

  integer errors;
  integer sample_idx;
  integer expected_idx;
  integer metric_print_idx;
  integer guard;
  integer file_handle;
  integer dpd_enable_arg;
  integer print_every;
  integer denom;
  integer err_bp;
  integer drift_bp;

  reg dpd_enable;
  reg signed [W-1:0] ref_i_now;
  reg signed [W-1:0] ref_q_now;
  reg signed [W-1:0] exp_i_now;
  reg signed [W-1:0] exp_q_now;
  reg signed [W-1:0] selected_i_now;
  reg signed [W-1:0] selected_q_now;
  reg signed [W-1:0] fb_i_now;
  reg signed [W-1:0] fb_q_now;

  gmp_engine #(
    .SAMPLE_WIDTH(W),
    .COEF_WIDTH(CW),
    .N_COEFS(N_COEFS),
    .COEF_ADDR_WIDTH(7)
  ) gmp (
    .clk(clk),
    .resetn(resetn),
    .enable(gmp_enable),
    .reload_coeffs(1'b0),
    .i_in(gmp_i_in),
    .q_in(gmp_q_in),
    .in_valid(gmp_in_valid),
    .in_ready(gmp_in_ready),
    .i_out(gmp_i_out),
    .q_out(gmp_q_out),
    .out_valid(gmp_out_valid),
    .out_ready(gmp_out_ready),
    .coef_addr(gmp_coef_addr),
    .coef_data(coef_data),
    .busy(gmp_busy)
  );

  metric_engine #(
    .SAMPLE_WIDTH(W),
    .CLIP_LEVEL(30000)
  ) metrics (
    .clk(clk),
    .resetn(resetn),
    .clear(clear),
    .ref_i(metric_ref_i),
    .ref_q(metric_ref_q),
    .fb_i(metric_fb_i),
    .fb_q(metric_fb_q),
    .sample_valid(metric_sample_valid),
    .dpd_i(metric_dpd_i),
    .dpd_q(metric_dpd_q),
    .dpd_valid(metric_dpd_valid),
    .threshold_error(threshold_error),
    .threshold_clip(threshold_clip),
    .threshold_drift(threshold_drift),
    .metric_power(metric_power),
    .metric_error(metric_error),
    .metric_clipping(metric_clipping),
    .metric_drift(metric_drift),
    .metrics_valid(metrics_valid),
    .retrain_request(retrain_request)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  always @* begin
    coef_data = coef_mem[gmp_coef_addr];
  end

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

  task print_metric_line;
    input integer idx;
    integer err_whole;
    integer err_frac;
    integer drift_whole;
    integer drift_frac;
    string err_pct_text;
    string drift_pct_text;
    begin
      denom = (metric_power == 0) ? 1 : metric_power;
      err_bp = (metric_error * 10000) / denom;
      drift_bp = (metric_drift * 10000) / denom;
      err_whole = err_bp / 100;
      err_frac = err_bp % 100;
      drift_whole = drift_bp / 100;
      drift_frac = drift_bp % 100;
      if (err_frac < 10)
        err_pct_text = $sformatf("%0d.0%0d%%", err_whole, err_frac);
      else
        err_pct_text = $sformatf("%0d.%0d%%", err_whole, err_frac);
      if (drift_frac < 10)
        drift_pct_text = $sformatf("%0d.0%0d%%", drift_whole, drift_frac);
      else
        drift_pct_text = $sformatf("%0d.%0d%%", drift_whole, drift_frac);
      $display("[METRIC] n=%0d dpd_enable=%0d fb_mode=%0s ref=(%0d,%0d) dpd=(%0d,%0d) fb=(%0d,%0d) power_l1_ewma=%0d error_ref_fb_l1_ewma=%0d err_rel=%0s drift_dpd_ref_l1_ewma=%0d drift_rel=%0s clipping_count=%0d retrain_request=%0d",
               idx,
               hist_dpd_enable[idx],
               fb_mode,
               hist_ref_i[idx],
               hist_ref_q[idx],
               hist_dpd_i[idx],
               hist_dpd_q[idx],
               hist_fb_i[idx],
               hist_fb_q[idx],
               metric_power,
               metric_error,
               err_pct_text,
               metric_drift,
               drift_pct_text,
               metric_clipping,
               retrain_request);
    end
  endtask

  always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      expected_idx <= 0;
      metric_print_idx <= 0;
      metric_ref_i <= '0;
      metric_ref_q <= '0;
      metric_fb_i <= '0;
      metric_fb_q <= '0;
      metric_sample_valid <= 1'b0;
      metric_dpd_i <= '0;
      metric_dpd_q <= '0;
      metric_dpd_valid <= 1'b0;
    end else begin
      metric_sample_valid <= 1'b0;
      metric_dpd_valid <= 1'b0;

      if (gmp_out_valid && expected_idx < N_EXPECTED) begin
        ref_i_now = sample_mem[expected_idx][31:16];
        ref_q_now = sample_mem[expected_idx][15:0];
        exp_i_now = expected_mem[expected_idx][31:16];
        exp_q_now = expected_mem[expected_idx][15:0];

        if ($isunknown(gmp_i_out) || $isunknown(gmp_q_out) ||
            $isunknown(exp_i_now) || $isunknown(exp_q_now)) begin
          errors = errors + 1;
          $display("[FAIL] GMP sample %0d has unknown value expected=(%0d,%0d) got=(%0d,%0d)",
                   expected_idx, exp_i_now, exp_q_now, gmp_i_out, gmp_q_out);
        end else if (gmp_i_out !== exp_i_now || gmp_q_out !== exp_q_now) begin
          errors = errors + 1;
          $display("[FAIL] GMP sample %0d expected=(%0d,%0d) got=(%0d,%0d)",
                   expected_idx, exp_i_now, exp_q_now, gmp_i_out, gmp_q_out);
        end

        selected_i_now = dpd_enable ? gmp_i_out : ref_i_now;
        selected_q_now = dpd_enable ? gmp_q_out : ref_q_now;

        if (fb_mode == "ref") begin
          fb_i_now = ref_i_now;
          fb_q_now = ref_q_now;
        end else begin
          fb_i_now = selected_i_now;
          fb_q_now = selected_q_now;
        end

        metric_ref_i <= ref_i_now;
        metric_ref_q <= ref_q_now;
        metric_fb_i <= fb_i_now;
        metric_fb_q <= fb_q_now;
        metric_sample_valid <= 1'b1;
        metric_dpd_i <= selected_i_now;
        metric_dpd_q <= selected_q_now;
        metric_dpd_valid <= 1'b1;

        hist_ref_i[expected_idx] <= ref_i_now;
        hist_ref_q[expected_idx] <= ref_q_now;
        hist_dpd_i[expected_idx] <= selected_i_now;
        hist_dpd_q[expected_idx] <= selected_q_now;
        hist_fb_i[expected_idx] <= fb_i_now;
        hist_fb_q[expected_idx] <= fb_q_now;
        hist_dpd_enable[expected_idx] <= dpd_enable;

        expected_idx <= expected_idx + 1;
      end

      if (metrics_valid && metric_print_idx < N_EXPECTED) begin
        if ((metric_print_idx % print_every) == 0 || metric_print_idx == N_EXPECTED-1)
          print_metric_line(metric_print_idx);
        metric_print_idx <= metric_print_idx + 1;
      end
    end
  end

  initial begin
    if (!$value$plusargs("COEF_HEX=%s", coef_path))
      coef_path = "/home/Ausilon/Desktop/dpd_v1/dpd_soc_min/datasets/opendpd_coeffs/coef_bank_openDPD.hex";
    if (!$value$plusargs("SAMPLES_HEX=%s", sample_path))
      sample_path = "/home/Ausilon/Desktop/dpd_v1/dpd_soc_min/datasets/opendpd_coeffs/gmp_opendpd_full_samples_iq_q15.hex";
    if (!$value$plusargs("EXPECTED_HEX=%s", expected_path))
      expected_path = "/home/Ausilon/Desktop/dpd_v1/dpd_soc_min/datasets/opendpd_coeffs/gmp_opendpd_full_expected_iq_q15.hex";
    if (!$value$plusargs("FB_MODE=%s", fb_mode))
      fb_mode = "loopback";
    if (!$value$plusargs("DPD_ENABLE=%d", dpd_enable_arg))
      dpd_enable_arg = 1;
    if (!$value$plusargs("PRINT_EVERY=%d", print_every))
      print_every = 1;
    if (print_every <= 0)
      print_every = 1;

    dpd_enable = (dpd_enable_arg != 0);

    $display("Loading coefficients: %s", coef_path);
    $display("Loading samples:      %s", sample_path);
    $display("Loading expected:     %s", expected_path);
    $display("Metric flow config:   DPD_ENABLE=%0d FB_MODE=%0s PRINT_EVERY=%0d", dpd_enable, fb_mode, print_every);
    $display("FB_MODE=loopback uses selected DPD/bypass output as feedback model.");
    $display("FB_MODE=ref uses ideal feedback equal to the reference input.");

    require_readable_file(coef_path);
    require_readable_file(sample_path);
    require_readable_file(expected_path);
    $readmemh(coef_path, coef_mem);
    $readmemh(sample_path, sample_mem);
    $readmemh(expected_path, expected_mem);

    errors = 0;
    resetn = 1'b0;
    clear = 1'b0;
    gmp_enable = 1'b0;
    gmp_i_in = '0;
    gmp_q_in = '0;
    gmp_in_valid = 1'b0;
    gmp_out_ready = 1'b1;
    threshold_error = 32'hffff_ffff;
    threshold_clip = 32'hffff_ffff;
    threshold_drift = 32'hffff_ffff;
    sample_idx = 0;
    guard = 0;

    repeat (4) @(posedge clk);
    resetn = 1'b1;
    repeat (2) @(posedge clk);
    gmp_enable = 1'b1;

    check(coef_mem[0] === 18'h005ED, "OpenDPD Q2.16 coefficient 0 real loaded");
    check(coef_mem[1] === 18'h00000, "OpenDPD Q2.16 coefficient 0 imag loaded");
    check(coef_mem[4] === 18'h0AC4E, "OpenDPD Q2.16 coefficient 2 real loaded");

    while (metric_print_idx < N_EXPECTED && guard < 4000) begin
      @(negedge clk);
      if (sample_idx < N_INPUTS && gmp_in_ready) begin
        gmp_i_in <= sample_mem[sample_idx][31:16];
        gmp_q_in <= sample_mem[sample_idx][15:0];
        gmp_in_valid <= 1'b1;
        sample_idx = sample_idx + 1;
      end else begin
        gmp_in_valid <= 1'b0;
      end
      guard = guard + 1;
    end

    @(negedge clk);
    gmp_in_valid <= 1'b0;
    repeat (4) @(posedge clk);

    check(sample_idx == N_INPUTS, "all input samples were accepted by GMP");
    check(expected_idx == N_EXPECTED, "all GMP outputs were produced");
    check(metric_print_idx == N_EXPECTED, "all metric samples were printed/processed");

    if (errors == 0) begin
      $display("\n[TB PASS] tb_metric_engine");
    end else begin
      $display("\n[TB FAIL] errors=%0d", errors);
      $fatal;
    end
    $finish;
  end
endmodule
