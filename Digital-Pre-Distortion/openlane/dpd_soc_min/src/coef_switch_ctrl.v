// ============================================================
// coef_switch_ctrl.v - Safe A/B coefficient bank switch control
// Switch happens only on sync_event while datapath is idle or at a
// deterministic symbol boundary.
// ============================================================
module coef_switch_ctrl (
    input  wire clk,
    input  wire resetn,
    input  wire request_switch,
    input  wire sync_event,
    input  wire datapath_idle,
    output reg  active_bank,      // 0=A, 1=B
    output reg  switch_pulse,
    output reg  busy,
    output reg  pending
);
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            active_bank  <= 1'b0;
            switch_pulse <= 1'b0;
            busy         <= 1'b0;
            pending      <= 1'b0;
        end else begin
            switch_pulse <= 1'b0;
            if (request_switch) begin
                pending <= 1'b1;
                busy    <= 1'b1;
            end
            if (pending && sync_event && datapath_idle) begin
                active_bank  <= ~active_bank;
                switch_pulse <= 1'b1;
                pending      <= 1'b0;
                busy         <= 1'b0;
            end
        end
    end
endmodule
