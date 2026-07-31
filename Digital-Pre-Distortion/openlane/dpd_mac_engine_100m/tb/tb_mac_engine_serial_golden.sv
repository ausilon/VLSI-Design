`timescale 1ns/1ps

module tb_mac_engine_serial_golden;
  localparam W = 16;
  localparam CW = 18;
  localparam CAW = 7;
  localparam RAW = 4;
  localparam N = 4;

  localparam signed [CW-1:0] GOLDEN_COEF2_REAL = 18'sd2225;
  localparam signed [CW-1:0] GOLDEN_COEF2_IMAG = -18'sd2119;
  localparam signed [CW-1:0] GOLDEN_COEF38_IMAG = -18'sd1;
  localparam [31:0] GOLDEN_STATUS_ERROR_ACC = 32'd99000;
  localparam signed [63:0] GOLDEN_EPOCH0_ACC2_REAL = 64'sd7980000;
  localparam signed [63:0] GOLDEN_EPOCH0_ACC2_IMAG = 64'sd0;
  localparam [63:0] GOLDEN_EPOCH0_DEN2 = 64'd15960000;
  localparam [63:0] GOLDEN_EPOCH0_MODEL_ERROR = 64'd3700;

  reg clk;
  reg resetn;
  reg train_start;
  reg capture_done;
  reg [RAW-1:0] train_sample_count;

  wire capture_lock;
  wire capture_release;
  wire mac_rd_en;
  wire [RAW-1:0] mac_rd_addr;
  reg [4*W-1:0] mac_rd_data;

  wire train_busy;
  wire train_done;
  wire train_error;
  wire coef_ready;
  wire coef_we;
  wire [CAW-1:0] coef_addr;
  wire signed [CW-1:0] coef_wdata;
  wire [31:0] status_error_acc;

  reg [4*W-1:0] capture_mem [0:N-1];
  reg signed [CW-1:0] coef_mem [0:127];

  integer errors;
  integer k;
  integer write_count;
  integer saw_capture_release;
  integer saw_epoch0;
  reg signed [63:0] epoch0_acc2_real;
  reg signed [63:0] epoch0_acc2_imag;
  reg [63:0] epoch0_den2;
  reg [63:0] epoch0_model_error;

  mac_engine #(
    .SAMPLE_WIDTH(W),
    .COEF_WIDTH(CW),
    .COEF_ADDR_WIDTH(CAW),
    .CAPTURE_ADDR_WIDTH(RAW),
    .TRAIN_COUNT_WIDTH(RAW)
  ) dut (
    .clk(clk),
    .resetn(resetn),
    .train_start(train_start),
    .capture_done(capture_done),
    .train_sample_count(train_sample_count),
    .capture_lock(capture_lock),
    .capture_release(capture_release),
    .mac_rd_en(mac_rd_en),
    .mac_rd_addr(mac_rd_addr),
    .mac_rd_data(mac_rd_data),
    .train_busy(train_busy),
    .train_done(train_done),
    .train_error(train_error),
    .coef_ready(coef_ready),
    .coef_we(coef_we),
    .coef_addr(coef_addr),
    .coef_wdata(coef_wdata),
    .status_error_acc(status_error_acc)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  always @* begin
    mac_rd_data = capture_mem[mac_rd_addr];
  end

  always @(posedge clk) begin
    if (resetn && coef_we) begin
      coef_mem[coef_addr] <= coef_wdata;
      write_count <= write_count + 1;
    end

    if (resetn && capture_release)
      saw_capture_release <= 1;

    if (resetn && dut.state == 5'd13 && dut.epoch_count == 5'd0 && !saw_epoch0) begin
      saw_epoch0 <= 1;
      epoch0_acc2_real <= dut.acc_num_real[2];
      epoch0_acc2_imag <= dut.acc_num_imag[2];
      epoch0_den2 <= dut.acc_den[2];
      epoch0_model_error <= dut.epoch_model_error_acc;
      $display("[EPOCH0] acc2_real=%0d acc2_imag=%0d den2=%0d model_error=%0d",
               dut.acc_num_real[2],
               dut.acc_num_imag[2],
               dut.acc_den[2],
               dut.epoch_model_error_acc);
    end
  end

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

  task load_linear_half_dataset;
    begin
      // Four-sample toy snapshot: FB = 2 * REF.
      // It is intentionally small, so the 39-term NLMS solution is not unique.
      capture_mem[0] = {16'sd1000,  -16'sd500,  16'sd2000,  -16'sd1000};
      capture_mem[1] = {-16'sd1500, 16'sd700,  -16'sd3000, 16'sd1400};
      capture_mem[2] = {16'sd2200,  16'sd1100, 16'sd4400,  16'sd2200};
      capture_mem[3] = {-16'sd800, -16'sd1200, -16'sd1600, -16'sd2400};
    end
  endtask

  task start_training;
    begin
      @(posedge clk);
      train_start <= 1'b1;
      @(posedge clk);
      train_start <= 1'b0;
    end
  endtask

  task wait_train_done;
    integer guard;
    begin
      guard = 0;
      while (!train_done && guard < 250000) begin
        @(posedge clk);
        guard = guard + 1;
      end
      check(train_done, "training completes");
    end
  endtask

  initial begin
    errors = 0;
    write_count = 0;
    saw_capture_release = 0;
    saw_epoch0 = 0;
    epoch0_acc2_real = 64'sd0;
    epoch0_acc2_imag = 64'sd0;
    epoch0_den2 = 64'd0;
    epoch0_model_error = 64'd0;

    for (k = 0; k < 128; k = k + 1)
      coef_mem[k] = 18'sh3ffff;

    resetn = 1'b0;
    train_start = 1'b0;
    capture_done = 1'b0;
    train_sample_count = N-1;
    load_linear_half_dataset();

    repeat (5) @(posedge clk);
    resetn = 1'b1;
    repeat (3) @(posedge clk);

    start_training();
    repeat (5) @(posedge clk);
    check(train_done && train_error && !coef_ready,
          "train_start without capture_done reports error");

    @(posedge clk);
    capture_done <= 1'b1;
    write_count <= 0;
    saw_capture_release <= 0;
    saw_epoch0 <= 0;

    start_training();
    repeat (4) @(posedge clk);
    check(train_busy && capture_lock, "training locks capture snapshot while busy");
    wait_train_done();
    repeat (2) @(posedge clk);

    check(!train_error, "training finishes without error");
    check(coef_ready, "coefficient ready asserted");
    check(saw_capture_release, "capture snapshot released at done");
    check(write_count == 78, "MACcore writes all 78 complex GMP coefficient words");
    check(saw_epoch0, "epoch 0 checkpoint observed");
    check(epoch0_acc2_real == GOLDEN_EPOCH0_ACC2_REAL,
          "epoch 0 term2 real numerator matches NLMS golden");
    check(epoch0_acc2_imag == GOLDEN_EPOCH0_ACC2_IMAG,
          "epoch 0 term2 imag numerator matches NLMS golden");
    check(epoch0_den2 == GOLDEN_EPOCH0_DEN2,
          "epoch 0 term2 denominator matches NLMS golden");
    check(epoch0_model_error == GOLDEN_EPOCH0_MODEL_ERROR,
          "epoch 0 model error matches NLMS golden");
    check(coef_mem[4] == GOLDEN_COEF2_REAL,
          "final best coef2 real matches software NLMS golden");
    check(coef_mem[5] == GOLDEN_COEF2_IMAG,
          "final best coef2 imag matches software NLMS golden");
    check(coef_mem[77] == GOLDEN_COEF38_IMAG,
          "final best coef38 imag matches software NLMS golden");
    check(status_error_acc == GOLDEN_STATUS_ERROR_ACC,
          "status_error_acc matches 11 processed epochs");

    $display("[GOLDEN] coef2=(%0d,%0d) coef38_imag=%0d status_error_acc=%0d writes=%0d",
             coef_mem[4], coef_mem[5], coef_mem[77], status_error_acc, write_count);

    if (errors == 0) begin
      $display("\n[TB PASS] tb_mac_engine_serial_golden");
    end else begin
      $display("\n[TB FAIL] errors=%0d", errors);
      $fatal;
    end
    $finish;
  end
endmodule
