/*`timescale 1ns/1ps
module tb_axi_uart_manual;
  reg clk, resetn; reg [11:0] awaddr, araddr; reg awvalid,wvalid,bready,arvalid,rready; reg [31:0] wdata; reg [3:0] wstrb; wire awready,wready,bvalid,arready,rvalid; wire [31:0] rdata; wire [1:0] bresp,rresp; wire tx; wire rx;
  integer errors, cov_axi_tx_write, cov_status_read, cov_rx_read, cov_tx_low, cov_tx_high, cov_bvalid, cov_rvalid;
  assign rx = tx;
  axi_uart dut(.clk(clk),.resetn(resetn),.s_axi_awaddr(awaddr),.s_axi_awvalid(awvalid),.s_axi_awready(awready),.s_axi_wdata(wdata),.s_axi_wstrb(wstrb),.s_axi_wvalid(wvalid),.s_axi_wready(wready),.s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),.s_axi_araddr(araddr),.s_axi_arvalid(arvalid),.s_axi_arready(arready),.s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rvalid(rvalid),.s_axi_rready(rready),.tx(tx),.rx(rx));
  initial clk=0; always #5 clk=~clk;
  task check; input cond; input [255:0] msg; begin if(!cond) begin errors=errors+1; $display("[FAIL] %0s t=%0t rdata=%h",msg,$time,rdata); end else $display("[PASS] %0s",msg); end endtask
  always @(posedge clk) if(resetn) begin if(bvalid) cov_bvalid<=cov_bvalid+1; if(rvalid) cov_rvalid<=cov_rvalid+1; end
  task axi_write; input [11:0] addr; input [31:0] data; begin @(posedge clk); awaddr<=addr; wdata<=data; awvalid<=1; wvalid<=1; bready<=1; @(posedge clk); awvalid<=0; wvalid<=0; while(!bvalid) @(posedge clk); @(posedge clk); if(addr==0) begin cov_axi_tx_write=cov_axi_tx_write+1; if(data[7:0]<8'h80) cov_tx_low=cov_tx_low+1; else cov_tx_high=cov_tx_high+1; end end endtask
  task axi_read; input [11:0] addr; output [31:0] data; begin @(posedge clk); araddr<=addr; arvalid<=1; rready<=1; @(posedge clk); arvalid<=0; while(!rvalid) @(posedge clk); data=rdata; if(addr==12'h8) cov_status_read=cov_status_read+1; if(addr==12'h4) cov_rx_read=cov_rx_read+1; @(posedge clk); end endtask
  task send_wait_read; input [7:0] b; reg [31:0] rd; integer guard; begin
    axi_write(12'h0,{24'd0,b}); guard=0; repeat(250) @(posedge clk); axi_read(12'h8,rd); check(rd[1]==1'b1,"UART RX valid set after loopback"); axi_read(12'h4,rd); check(rd[7:0]==b,"AXI UART RX_DATA matches looped TX byte");
  end endtask
  task report_manual_coverage; begin
    $display("\n==== MANUAL COVERAGE: tb_axi_uart_manual ====");
    $display("tx_write=%0d status_read=%0d rx_read=%0d tx_low=%0d tx_high=%0d bvalid=%0d rvalid=%0d",cov_axi_tx_write,cov_status_read,cov_rx_read,cov_tx_low,cov_tx_high,cov_bvalid,cov_rvalid);
    check(cov_axi_tx_write>=2,"coverage: multiple AXI TX writes"); check(cov_status_read>=2 && cov_rx_read>=2,"coverage: status and RX reads"); check(cov_tx_low>0 && cov_tx_high>0,"coverage: low/high TX byte values"); check(cov_bvalid>0 && cov_rvalid>0,"coverage: AXI responses");
  end endtask
  initial begin
    errors=0; cov_axi_tx_write=0; cov_status_read=0; cov_rx_read=0; cov_tx_low=0; cov_tx_high=0; cov_bvalid=0; cov_rvalid=0;
    resetn=0; awaddr=0; araddr=0; awvalid=0; wvalid=0; bready=0; arvalid=0; rready=0; wdata=0; wstrb=4'hf; repeat(4) @(posedge clk); resetn=1; repeat(5) @(posedge clk);
    send_wait_read(8'h55); send_wait_read(8'ha5);
    report_manual_coverage(); if(errors==0) $display("\n[TB PASS] tb_axi_uart_manual"); else begin $display("\n[TB FAIL] errors=%0d",errors); $fatal; end $finish;
  end
endmodule
*/
`timescale 1ns/1ps

module tb_axi_uart_manual;

  reg clk, resetn;

  reg [11:0] awaddr, araddr;
  reg awvalid, wvalid, bready, arvalid, rready;
  reg [31:0] wdata;
  reg [3:0] wstrb;

  wire awready, wready, bvalid, arready, rvalid;
  wire [31:0] rdata;
  wire [1:0] bresp, rresp;

  wire tx, rx;
  assign rx = tx;

  integer errors;
  integer cov_axi_tx_write, cov_status_read, cov_rx_read;
  integer cov_tx_low, cov_tx_high, cov_bvalid, cov_rvalid;

  reg [7:0] expected_q[$];

  //--------------------------------------------------
  // DUT
  //--------------------------------------------------
  axi_uart dut(
    .clk(clk), .resetn(resetn),
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
    .tx(tx),
    .rx(rx)
  );

  //--------------------------------------------------
  // clock
  //--------------------------------------------------
  initial clk = 0;
  always #5 clk = ~clk;

  //--------------------------------------------------
  // error helper
  //--------------------------------------------------
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

  always @(posedge clk) begin
    if (resetn) begin
      if (bvalid) cov_bvalid <= cov_bvalid + 1;
      if (rvalid) cov_rvalid <= cov_rvalid + 1;
    end
  end

  //--------------------------------------------------
  // AXI WRITE (com handshake mais seguro)
  //--------------------------------------------------
  task axi_write;
    input [11:0] addr;
    input [31:0] data;

    integer guard;
    begin
      @(posedge clk);
      awaddr  <= addr;
      wdata   <= data;
      awvalid <= 1;
      wvalid  <= 1;
      bready  <= 1;

      guard = 0;

      // espera handshake
      while (!bvalid && guard < 200) begin
        @(posedge clk);
        guard = guard + 1;
      end

      check(bvalid, "AXI write response received");

      awvalid <= 0;
      wvalid  <= 0;

      if (guard >= 200) begin
        errors++;
        $display("[FAIL] AXI write timeout");
      end

      if (addr == 12'h0) begin
        cov_axi_tx_write++;
        if (data[7:0] < 8'h80) cov_tx_low++;
        else cov_tx_high++;
        expected_q.push_back(data[7:0]);
      end
    end
  endtask

  //--------------------------------------------------
  // AXI READ (com timeout)
  //--------------------------------------------------
  task axi_read;
    input  [11:0] addr;
    output [31:0] data;

    integer guard;
    begin
      @(posedge clk);
      araddr  <= addr;
      arvalid <= 1;
      rready  <= 1;

      guard = 0;

      while (!rvalid && guard < 200) begin
        @(posedge clk);
        guard = guard + 1;
      end

      if (guard >= 200) begin
        errors++;
        $display("[FAIL] AXI read timeout addr=%h", addr);
      end

      data = rdata;

      arvalid <= 0;

      if (addr == 12'h8) cov_status_read++;
      if (addr == 12'h4) cov_rx_read++;

      @(posedge clk);
    end
  endtask

  //--------------------------------------------------
  // CORE CHECK
  //--------------------------------------------------
  task send_wait_read;
    input [7:0] b;
    reg [31:0] rd;
    integer guard;
    begin
      axi_write(12'h0, {24'd0, b});

      // espera propagação UART
      guard = 0;
      while (guard < 500) begin
        @(posedge clk);
        guard++;
      end

      axi_read(12'h8, rd);
      check(rd[1], "UART RX valid set after loopback");

      axi_read(12'h4, rd);
      check(rd[7:0] == b, "AXI RX_DATA match TX byte");
    end
  endtask

  //--------------------------------------------------
  // RESET DURANTE OPERAÇÃO
  //--------------------------------------------------
  task reset_during_op;
    reg [31:0] rd;
    begin
      @(posedge clk);
      axi_write(12'h0, 32'hA5);

      repeat(10) @(posedge clk);

      resetn <= 0;
      repeat(5) @(posedge clk);
      resetn <= 1;

      repeat(20) @(posedge clk);

      axi_read(12'h8, rd);
      check(rd[1] == 1'b0 && rd[0] == 1'b1, "reset leaves UART idle with RX invalid");
    end
  endtask

  //--------------------------------------------------
  // RANDOM STRESS
  //--------------------------------------------------
  task random_test;
    integer i;
    reg [7:0] rnd;
    begin
      for (i = 0; i < 20; i = i + 1) begin
        rnd = $random;
        send_wait_read(rnd);
      end
    end
  endtask

  //--------------------------------------------------
  // COVERAGE REPORT
  //--------------------------------------------------
  task report_manual_coverage;
    begin
      $display("\n==== MANUAL COVERAGE: tb_axi_uart_manual ====");
      $display("tx_write=%0d status_read=%0d rx_read=%0d",
               cov_axi_tx_write, cov_status_read, cov_rx_read);
      $display("tx_low=%0d tx_high=%0d bvalid=%0d rvalid=%0d",
               cov_tx_low, cov_tx_high, cov_bvalid, cov_rvalid);

      check(cov_axi_tx_write >= 2, "AXI TX writes");
      check(cov_status_read >= 2 && cov_rx_read >= 2, "status/RX reads");
      check(cov_tx_low > 0 && cov_tx_high > 0, "low/high coverage");
      check(cov_bvalid > 0 && cov_rvalid > 0, "AXI response valid pulses");
    end
  endtask

  //--------------------------------------------------
  // MAIN
  //--------------------------------------------------
  initial begin
    errors = 0;

    cov_axi_tx_write = 0;
    cov_status_read  = 0;
    cov_rx_read      = 0;
    cov_tx_low       = 0;
    cov_tx_high      = 0;
    cov_bvalid       = 0;
    cov_rvalid       = 0;

    resetn = 0;
    awaddr = 0;
    araddr = 0;
    awvalid = 0;
    wvalid = 0;
    bready = 0;
    arvalid = 0;
    rready = 0;
    wdata = 0;
    wstrb = 4'hF;

    repeat (5) @(posedge clk);
    resetn = 1;
    repeat (5) @(posedge clk);
    $display("awready=%b wready=%b bvalid=%b arready=%b rvalid=%b",
         awready, wready, bvalid, arready, rvalid);

    // testes base
    send_wait_read(8'h55);
    send_wait_read(8'hA5);

    // burst
    send_wait_read(8'h12);
    send_wait_read(8'h34);
    send_wait_read(8'h56);
    send_wait_read(8'h78);

    // random stress
    random_test();

    // reset during operation
    reset_during_op();

    report_manual_coverage();

    if (errors == 0)
      $display("\n[TB PASS] tb_axi_uart_manual");
    else begin
      $display("\n[TB FAIL] errors=%0d", errors);
      $fatal;
    end

    $finish;
  end

endmodule
