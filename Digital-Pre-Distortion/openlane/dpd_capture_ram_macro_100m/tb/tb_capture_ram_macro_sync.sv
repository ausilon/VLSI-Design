`timescale 1ns/1ps
module tb_capture_ram_macro_sync;
    reg clk = 1'b0;
    reg resetn = 1'b0;
    reg start = 1'b0;
    reg [9:0] capture_len = 10'd513;
    reg signed [15:0] ref_i = 16'sd0;
    reg signed [15:0] ref_q = 16'sd0;
    reg signed [15:0] fb_i = 16'sd0;
    reg signed [15:0] fb_q = 16'sd0;
    reg sample_valid = 1'b0;
    reg snapshot_lock = 1'b0;
    reg [9:0] rd_addr = 10'd0;
    wire [63:0] rd_data;
    wire busy;
    wire done;
    wire snapshot_page;
    wire capture_ready;
    integer idx;
    integer errors = 0;

    capture_ram_macro dut (.*);
    always #5 clk = ~clk;

    function automatic [63:0] expected_word(input integer sample_idx);
        reg signed [15:0] e_ref_i;
        reg signed [15:0] e_ref_q;
        reg signed [15:0] e_fb_i;
        reg signed [15:0] e_fb_q;
        begin
            e_ref_i = sample_idx;
            e_ref_q = sample_idx + 1000;
            e_fb_i  = -sample_idx;
            e_fb_q  = 2000 - sample_idx;
            expected_word = {e_ref_i, e_ref_q, e_fb_i, e_fb_q};
        end
    endfunction

    task automatic check_read(input [9:0] address);
        begin
            @(negedge clk);
            rd_addr = address;
            repeat (3) @(posedge clk);
            #2;
            if (rd_data !== expected_word(address)) begin
                $display("[FAIL] addr=%0d expected=%h got=%h",
                         address, expected_word(address), rd_data);
                errors = errors + 1;
            end else begin
                $display("[PASS] synchronous read addr=%0d data=%h",
                         address, rd_data);
            end
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        resetn = 1'b1;

        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        for (idx = 0; idx <= 513; idx = idx + 1) begin
            ref_i = idx;
            ref_q = idx + 1000;
            fb_i = -idx;
            fb_q = 2000 - idx;
            sample_valid = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
        end
        sample_valid = 1'b0;
        @(posedge clk);
        #1;

        if (!done || !snapshot_page) begin
            $display("[FAIL] capture completion done=%b page=%b", done, snapshot_page);
            errors = errors + 1;
        end

        check_read(10'd0);
        check_read(10'd511);
        check_read(10'd512);
        check_read(10'd513);

        if (errors == 0)
            $display("[TB PASS] capture RAM synchronous bank selection");
        else
            $fatal(1, "[TB FAIL] errors=%0d", errors);
        $finish;
    end
endmodule
