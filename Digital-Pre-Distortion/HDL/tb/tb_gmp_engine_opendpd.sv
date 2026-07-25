`timescale 1ns/1ps

module tb_gmp_engine_opendpd;
  localparam W = 16;
  localparam CW = 18;
  localparam N_COEFS = 128;
  localparam N_INPUTS = 66;
  localparam N_EXPECTED = 64;

  reg clk;
  reg resetn;
  reg enable;
  reg signed [W-1:0] i_in;
  reg signed [W-1:0] q_in;
  reg in_valid;
  reg out_ready;

  wire in_ready;
  wire signed [W-1:0] i_out;
  wire signed [W-1:0] q_out;
  wire out_valid;
  wire [6:0] coef_addr;
  wire busy;

  reg signed [CW-1:0] coef_mem [0:N_COEFS-1];
  reg [31:0] sample_mem [0:N_INPUTS-1];
  reg [31:0] expected_mem [0:N_EXPECTED-1];
  reg signed [CW-1:0] coef_data;

  string coef_path;
  string sample_path;
  string expected_path;
  integer errors;
  integer sample_idx;
  integer expected_idx;
  integer sent_count;
  integer guard;
  integer file_handle;
  reg signed [W-1:0] exp_i;
  reg signed [W-1:0] exp_q;

  gmp_engine #(
    .SAMPLE_WIDTH(W),
    .COEF_WIDTH(CW),
    .N_COEFS(N_COEFS),
    .COEF_ADDR_WIDTH(7)
  ) dut (
    .clk(clk),
    .resetn(resetn),
    .enable(enable),
    .reload_coeffs(1'b0),
    .i_in(i_in),
    .q_in(q_in),
    .in_valid(in_valid),
    .in_ready(in_ready),
    .i_out(i_out),
    .q_out(q_out),
    .out_valid(out_valid),
    .out_ready(out_ready),
    .coef_addr(coef_addr),
    .coef_data(coef_data),
    .busy(busy)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  always @* begin
    coef_data = coef_mem[coef_addr];
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

  task send_and_check;
    input integer idx;
    begin
      guard = 0;
      while (!in_ready && guard < 100) begin
        @(posedge clk);
        guard = guard + 1;
      end
      check(in_ready, "gmp_engine ready for input sample");

      @(posedge clk);
      i_in <= sample_mem[idx][31:16];
      q_in <= sample_mem[idx][15:0];
      in_valid <= 1'b1;
      @(posedge clk);
      in_valid <= 1'b0;

      if (idx >= 2) begin
        expected_idx = idx - 2;
        guard = 0;
        while (!out_valid && guard < 200) begin
          @(posedge clk);
          guard = guard + 1;
        end
        check(out_valid, "gmp_engine produced output");

        exp_i = expected_mem[expected_idx][31:16];
        exp_q = expected_mem[expected_idx][15:0];
        if ($isunknown(i_out) || $isunknown(q_out) || $isunknown(exp_i) || $isunknown(exp_q)) begin
          errors = errors + 1;
          $display("[FAIL] sample %0d contains unknown values: expected I=%0d Q=%0d got I=%0d Q=%0d",
                   expected_idx, exp_i, exp_q, i_out, q_out);
        end else if (i_out !== exp_i || q_out !== exp_q) begin
          errors = errors + 1;
          $display("[FAIL] sample %0d expected I=%0d Q=%0d got I=%0d Q=%0d",
                   expected_idx, exp_i, exp_q, i_out, q_out);
        end else begin
          $display("[PASS] sample %0d I=%0d Q=%0d", expected_idx, i_out, q_out);
        end
      end

      @(posedge clk);
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

  initial begin
    if (!$value$plusargs("COEF_HEX=%s", coef_path))
      coef_path = "/home/Ausilon/Desktop/dpd_v1/dpd_soc_min/datasets/opendpd_coeffs/coef_bank_openDPD.hex";
    if (!$value$plusargs("SAMPLES_HEX=%s", sample_path))
      sample_path = "/home/Ausilon/Desktop/dpd_v1/dpd_soc_min/datasets/opendpd_coeffs/gmp_opendpd_full_samples_iq_q15.hex";
    if (!$value$plusargs("EXPECTED_HEX=%s", expected_path))
      expected_path = "/home/Ausilon/Desktop/dpd_v1/dpd_soc_min/datasets/opendpd_coeffs/gmp_opendpd_full_expected_iq_q15.hex";

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
    resetn = 1'b0;
    enable = 1'b0;
    i_in = '0;
    q_in = '0;
    in_valid = 1'b0;
    out_ready = 1'b1;

    repeat (4) @(posedge clk);
    resetn = 1'b1;
    repeat (2) @(posedge clk);
    enable = 1'b0;

    check(coef_mem[0] === 18'h005ED, "OpenDPD Q2.16 coefficient 0 real loaded");
    check(coef_mem[1] === 18'h00000, "OpenDPD Q2.16 coefficient 0 imag loaded");
    check(coef_mem[4] === 18'h0AC4E, "OpenDPD Q2.16 coefficient 2 real loaded");

    sample_idx = 0;
    expected_idx = 0;
    sent_count = 0;
    guard = 0;
    while (expected_idx < N_EXPECTED && guard < 2000) begin
      @(negedge clk);
      if (sample_idx < N_INPUTS && in_ready) begin
        i_in <= sample_mem[sample_idx][31:16];
        q_in <= sample_mem[sample_idx][15:0];
        in_valid <= 1'b1;
        sample_idx = sample_idx + 1;
        sent_count = sent_count + 1;
      end else begin
        in_valid <= 1'b0;
      end

      @(posedge clk);
      #1;
      if (out_valid) begin
        exp_i = expected_mem[expected_idx][31:16];
        exp_q = expected_mem[expected_idx][15:0];
        if ($isunknown(i_out) || $isunknown(q_out) || $isunknown(exp_i) || $isunknown(exp_q)) begin
          errors = errors + 1;
          $display("[FAIL] sample %0d contains unknown values: expected I=%0d Q=%0d got I=%0d Q=%0d",
                   expected_idx, exp_i, exp_q, i_out, q_out);
        end else if (i_out !== exp_i || q_out !== exp_q) begin
          errors = errors + 1;
          $display("[FAIL] sample %0d expected I=%0d Q=%0d got I=%0d Q=%0d",
                   expected_idx, exp_i, exp_q, i_out, q_out);
        end else begin
          $display("[PASS] sample %0d I=%0d Q=%0d", expected_idx, i_out, q_out);
        end
        expected_idx = expected_idx + 1;
      end
      guard = guard + 1;
    end
    in_valid <= 1'b0;

    check(sample_idx == N_INPUTS, "all input samples were accepted");
    check(expected_idx == N_EXPECTED, "all expected outputs were produced");

    if (errors == 0) begin
      $display("\n[TB PASS] tb_gmp_engine_opendpd");
    end else begin
      $display("\n[TB FAIL] errors=%0d", errors);
      $fatal;
    end
    $finish;
  end
endmodule
