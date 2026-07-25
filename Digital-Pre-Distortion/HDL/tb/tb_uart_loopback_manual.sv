`timescale 1ns/1ps

module tb_uart_loopback_manual;
  reg clk;
  reg reset;
  reg [7:0] data_in;
  reg tx_start;
  wire tx;
  wire tx_done;
  wire [7:0] data_out;
  wire rx_done;

  integer errors;
  integer cov_tx_start_hits;
  integer cov_tx_done_hits;
  integer cov_rx_done_hits;
  integer cov_byte_00;
  integer cov_byte_ff;
  integer cov_byte_55;
  integer cov_byte_aa;
  integer cov_other_bytes;
  integer cov_loopback_pass;
  integer cov_loopback_fail;

  uart_tx u_tx (.clk(clk), .reset(reset), .data_in(data_in), .tx_start(tx_start), .tx(tx), .tx_done(tx_done));
  uart_rx u_rx (.clk(clk), .reset(reset), .rx(tx), .data_out(data_out), .rx_done(rx_done));

  initial clk = 1'b0;
  always #5 clk = ~clk;

  always @(posedge clk) begin
    if (reset) begin
      cov_tx_done_hits <= 0;
      cov_rx_done_hits <= 0;
    end else begin
      if (tx_done) cov_tx_done_hits <= cov_tx_done_hits + 1;
      if (rx_done) cov_rx_done_hits <= cov_rx_done_hits + 1;
    end
  end

  task check;
    input condition;
    input [255:0] msg;
    begin
      if (!condition) begin
        errors = errors + 1;
        $display("[FAIL] %0s at t=%0t", msg, $time);
      end else begin
        $display("[PASS] %0s", msg);
      end
    end
  endtask

  task send_and_check;
    input [7:0] b;
    integer guard;
    begin
      @(posedge clk);
      data_in <= b;
      tx_start <= 1'b1;
      cov_tx_start_hits = cov_tx_start_hits + 1;
      case (b)
        8'h00: cov_byte_00 = cov_byte_00 + 1;
        8'hff: cov_byte_ff = cov_byte_ff + 1;
        8'h55: cov_byte_55 = cov_byte_55 + 1;
        8'haa: cov_byte_aa = cov_byte_aa + 1;
        default: cov_other_bytes = cov_other_bytes + 1;
      endcase
      @(posedge clk);
      tx_start <= 1'b0;

      guard = 0;
      while (!rx_done && guard < 1000) begin
        guard = guard + 1;
        @(posedge clk);
      end

      if (rx_done && data_out == b) begin
        cov_loopback_pass = cov_loopback_pass + 1;
        $display("[PASS] UART loopback byte 0x%02h", b);
      end else begin
        cov_loopback_fail = cov_loopback_fail + 1;
        errors = errors + 1;
        $display("[FAIL] UART loopback expected 0x%02h got 0x%02h rx_done=%0b", b, data_out, rx_done);
      end
      repeat (5) @(posedge clk);
    end
  endtask

  task report_manual_coverage;
    begin
      $display("\n==== MANUAL COVERAGE: tb_uart_loopback_manual ====");
      $display("tx_start_hits     = %0d", cov_tx_start_hits);
      $display("tx_done_hits      = %0d", cov_tx_done_hits);
      $display("rx_done_hits      = %0d", cov_rx_done_hits);
      $display("byte_00_hits      = %0d", cov_byte_00);
      $display("byte_ff_hits      = %0d", cov_byte_ff);
      $display("byte_55_hits      = %0d", cov_byte_55);
      $display("byte_aa_hits      = %0d", cov_byte_aa);
      $display("other_byte_hits   = %0d", cov_other_bytes);
      $display("loopback_pass     = %0d", cov_loopback_pass);
      $display("loopback_fail     = %0d", cov_loopback_fail);
      check(cov_tx_start_hits >= 5, "coverage: multiple TX starts");
      check(cov_tx_done_hits  >= 5, "coverage: multiple TX done pulses");
      check(cov_rx_done_hits  >= 5, "coverage: multiple RX done pulses");
      check(cov_byte_00 > 0 && cov_byte_ff > 0 && cov_byte_55 > 0 && cov_byte_aa > 0, "coverage: corner bytes exercised");
      check(cov_loopback_fail == 0, "coverage/check: no loopback failures");
    end
  endtask

  initial begin
    errors = 0;
    cov_tx_start_hits = 0; cov_tx_done_hits = 0; cov_rx_done_hits = 0;
    cov_byte_00 = 0; cov_byte_ff = 0; cov_byte_55 = 0; cov_byte_aa = 0; cov_other_bytes = 0;
    cov_loopback_pass = 0; cov_loopback_fail = 0;
    reset = 1'b1; tx_start = 1'b0; data_in = 8'h00;
    repeat (5) @(posedge clk);
    reset = 1'b0;
    repeat (3) @(posedge clk);

    send_and_check(8'h00);
    send_and_check(8'hff);
    send_and_check(8'h55);
    send_and_check(8'haa);
    send_and_check(8'h3c);

    report_manual_coverage();
    if (errors == 0) $display("\n[TB PASS] tb_uart_loopback_manual");
    else begin $display("\n[TB FAIL] tb_uart_loopback_manual errors=%0d", errors); $fatal; end
    $finish;
  end
endmodule
