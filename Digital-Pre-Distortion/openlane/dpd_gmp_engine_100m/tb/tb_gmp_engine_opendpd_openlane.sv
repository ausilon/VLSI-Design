`timescale 1ns/1ps

module tb_gmp_engine_opendpd_openlane;
  localparam W = 16;
  localparam CW = 18;
  localparam N_COEFS = 128;
  localparam N_INPUTS = 66;
  localparam N_EXPECTED = 64;

  reg clk = 1'b0;
  reg resetn = 1'b0;
  reg enable = 1'b1;
  reg signed [W-1:0] i_in = '0;
  reg signed [W-1:0] q_in = '0;
  reg in_valid = 1'b0;
  reg out_ready = 1'b1;

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
  integer errors = 0;
  integer sample_idx = 0;
  integer expected_idx = 0;
  integer flush_count = 0;
  integer guard = 0;
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

  always #5 clk = ~clk;
  always @* coef_data = coef_mem[coef_addr];

  task require_readable_file;
    input string path;
    begin
      file_handle = $fopen(path, "r");
      if (file_handle == 0) begin
        $display("[FATAL] Cannot open required file: %s", path);
        $fatal;
      end
      $fclose(file_handle);
    end
  endtask

  initial begin
    if (!$value$plusargs("COEF_HEX=%s", coef_path))
      $fatal(1, "Missing +COEF_HEX=<path>");
    if (!$value$plusargs("SAMPLES_HEX=%s", sample_path))
      $fatal(1, "Missing +SAMPLES_HEX=<path>");
    if (!$value$plusargs("EXPECTED_HEX=%s", expected_path))
      $fatal(1, "Missing +EXPECTED_HEX=<path>");

    require_readable_file(coef_path);
    require_readable_file(sample_path);
    require_readable_file(expected_path);
    $readmemh(coef_path, coef_mem);
    $readmemh(sample_path, sample_mem);
    $readmemh(expected_path, expected_mem);

    repeat (4) @(posedge clk);
    resetn = 1'b1;
    repeat (2) @(posedge clk);

    if (coef_mem[0] !== 18'h005ED ||
        coef_mem[1] !== 18'h00000 ||
        coef_mem[4] !== 18'h0AC4E) begin
      $display("[FAIL] OpenDPD coefficient bank audit");
      $fatal;
    end

    while (expected_idx < N_EXPECTED && guard < 50000) begin
      @(negedge clk);
      if (in_ready) begin
        in_valid <= 1'b1;
        if (sample_idx < N_INPUTS) begin
          i_in <= sample_mem[sample_idx][31:16];
          q_in <= sample_mem[sample_idx][15:0];
          sample_idx = sample_idx + 1;
        end else begin
          i_in <= '0;
          q_in <= '0;
          flush_count = flush_count + 1;
        end
      end else begin
        in_valid <= 1'b0;
      end

      @(posedge clk);
      #1;
      if (out_valid && expected_idx < N_EXPECTED) begin
        exp_i = expected_mem[expected_idx][31:16];
        exp_q = expected_mem[expected_idx][15:0];
        if ($isunknown(i_out) || $isunknown(q_out) ||
            i_out !== exp_i || q_out !== exp_q) begin
          errors = errors + 1;
          $display("[FAIL] sample %0d expected I=%0d Q=%0d got I=%0d Q=%0d",
                   expected_idx, exp_i, exp_q, i_out, q_out);
        end
        expected_idx = expected_idx + 1;
      end
      guard = guard + 1;
    end

    if (sample_idx != N_INPUTS) begin
      errors = errors + 1;
      $display("[FAIL] accepted inputs=%0d expected=%0d", sample_idx, N_INPUTS);
    end
    if (expected_idx != N_EXPECTED) begin
      errors = errors + 1;
      $display("[FAIL] produced outputs=%0d expected=%0d",
               expected_idx, N_EXPECTED);
    end

    $display("[AUDIT] inputs=%0d outputs=%0d extra_flush=%0d cycles=%0d",
             sample_idx, expected_idx, flush_count, guard);
    if (errors == 0)
      $display("[TB PASS] tb_gmp_engine_opendpd_openlane");
    else begin
      $display("[TB FAIL] errors=%0d", errors);
      $fatal;
    end
    $finish;
  end
endmodule
