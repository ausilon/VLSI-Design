// ============================================================
// gmp_engine.v - OpenLane timing-oriented 39-term GMP engine
//
// Contract:
//   - Q1.15 signed I/Q samples
//   - complex Q2.16 coefficients stored as:
//       addr 2*k+0 = Re{coef[k]}
//       addr 2*k+1 = Im{coef[k]}
//   - 39 OpenDPD GMP terms
//   - two-sample lookahead in the output sequence
//
// Architecture:
//   - 10 pipelined MAC lanes
//   - 4 issue phases per output sample, covering 40 slots
//   - term slot 39 is forced to zero
//   - II = 4 cycles in steady state
//   - exact RTL magnitude is preserved; input magnitude/powers are computed by
//     a fixed-latency feature pipeline before entering the GMP window
//   - lane multiplication and complex accumulation are registered separately
// ============================================================
module gmp_engine #(
    parameter SAMPLE_WIDTH = 16,
    parameter COEF_WIDTH = 18,
    parameter N_COEFS = 128,
    parameter COEF_ADDR_WIDTH = 7
)(
    input  wire clk,
    input  wire resetn,
    input  wire enable,
    input  wire reload_coeffs,
    input  wire signed [SAMPLE_WIDTH-1:0] i_in,
    input  wire signed [SAMPLE_WIDTH-1:0] q_in,
    input  wire in_valid,
    output wire in_ready,
    output reg  signed [SAMPLE_WIDTH-1:0] i_out,
    output reg  signed [SAMPLE_WIDTH-1:0] q_out,
    output reg  out_valid,
    input  wire out_ready,
    output reg  [COEF_ADDR_WIDTH-1:0] coef_addr,
    input  wire signed [COEF_WIDTH-1:0] coef_data,
    output wire busy
);
    localparam N_TERMS = 39;
    localparam [5:0] N_TERMS_SIZED = 6'd39;
    localparam N_COEF_WORDS = 2 * N_TERMS;
    localparam LANES = 10;
    localparam [5:0] LANES_SIZED = 6'd10;
    localparam PHASE_LAST = 2'd3;

    localparam STATE_LOAD   = 3'd0;
    localparam STATE_RUN    = 3'd1;
    localparam STATE_ISSUE1 = 3'd2;
    localparam STATE_ISSUE2 = 3'd3;
    localparam STATE_ISSUE3 = 3'd4;

    reg [2:0] state;
    reg coeff_loaded;
    reg [COEF_ADDR_WIDTH-1:0] load_addr;
    reg [2:0] valid_count;
    reg active_slot;
    reg next_slot;
    reg [1:0] raw_cooldown;

    reg signed [COEF_WIDTH-1:0] coef_real [0:N_TERMS-1];
    reg signed [COEF_WIDTH-1:0] coef_imag [0:N_TERMS-1];

    reg signed [SAMPLE_WIDTH-1:0] x_i0, x_q0;
    reg signed [SAMPLE_WIDTH-1:0] x_i1, x_q1;
    reg signed [SAMPLE_WIDTH-1:0] x_i2, x_q2;
    reg signed [SAMPLE_WIDTH-1:0] x_i3, x_q3;
    reg signed [SAMPLE_WIDTH-1:0] x_i4, x_q4;
    reg [15:0] x_m0, x_m1, x_m2, x_m3, x_m4;
    reg [15:0] x_p20, x_p21, x_p22, x_p23, x_p24;
    reg [15:0] x_p30, x_p31, x_p32, x_p33, x_p34;
    reg [15:0] x_p40, x_p41, x_p42, x_p43, x_p44;

    reg signed [SAMPLE_WIDTH-1:0] w_i0, w_q0;
    reg signed [SAMPLE_WIDTH-1:0] w_i1, w_q1;
    reg signed [SAMPLE_WIDTH-1:0] w_i2, w_q2;
    reg signed [SAMPLE_WIDTH-1:0] w_i3, w_q3;
    reg signed [SAMPLE_WIDTH-1:0] w_i4, w_q4;
    reg [15:0] w_m0, w_m1, w_m2, w_m3, w_m4;
    reg [15:0] w_p20, w_p21, w_p22, w_p23, w_p24;
    reg [15:0] w_p30, w_p31, w_p32, w_p33, w_p34;
    reg [15:0] w_p40, w_p41, w_p42, w_p43, w_p44;

    reg signed [47:0] acc_i [0:1];
    reg signed [47:0] acc_q [0:1];

    reg feat_s0_valid;
    reg signed [SAMPLE_WIDTH-1:0] feat_s0_i;
    reg signed [SAMPLE_WIDTH-1:0] feat_s0_q;

    reg feat_s1_valid;
    reg signed [SAMPLE_WIDTH-1:0] feat_s1_i;
    reg signed [SAMPLE_WIDTH-1:0] feat_s1_q;
    reg [31:0] feat_s1_mag2;

    wire sqrt_valid;
    wire [15:0] sqrt_mag;
    reg signed [SAMPLE_WIDTH-1:0] sqrt_i_pipe [0:16];
    reg signed [SAMPLE_WIDTH-1:0] sqrt_q_pipe [0:16];
    reg sqrt_side_valid [0:16];

    reg feat_s2_valid;
    reg signed [SAMPLE_WIDTH-1:0] feat_s2_i;
    reg signed [SAMPLE_WIDTH-1:0] feat_s2_q;
    reg [15:0] feat_s2_m;
    reg [15:0] feat_s2_p2;

    reg feat_s3_valid;
    reg signed [SAMPLE_WIDTH-1:0] feat_s3_i;
    reg signed [SAMPLE_WIDTH-1:0] feat_s3_q;
    reg [15:0] feat_s3_m;
    reg [15:0] feat_s3_p2;
    reg [15:0] feat_s3_p3;

    reg feat_valid;
    reg signed [SAMPLE_WIDTH-1:0] feat_i;
    reg signed [SAMPLE_WIDTH-1:0] feat_q;
    reg [15:0] feat_m;
    reg [15:0] feat_p2;
    reg [15:0] feat_p3;
    reg [15:0] feat_p4;

    wire can_accept_output = !out_valid || out_ready;
    wire raw_ready = coeff_loaded && (raw_cooldown == 2'd0);
    assign in_ready = enable ? raw_ready : can_accept_output;
    assign busy = enable && (!coeff_loaded || (state != STATE_RUN) || !can_accept_output || (raw_cooldown != 2'd0));

    wire signed [SAMPLE_WIDTH-1:0] n_i0 = x_i1;
    wire signed [SAMPLE_WIDTH-1:0] n_q0 = x_q1;
    wire signed [SAMPLE_WIDTH-1:0] n_i1 = x_i2;
    wire signed [SAMPLE_WIDTH-1:0] n_q1 = x_q2;
    wire signed [SAMPLE_WIDTH-1:0] n_i2 = x_i3;
    wire signed [SAMPLE_WIDTH-1:0] n_q2 = x_q3;
    wire signed [SAMPLE_WIDTH-1:0] n_i3 = x_i4;
    wire signed [SAMPLE_WIDTH-1:0] n_q3 = x_q4;
    wire signed [SAMPLE_WIDTH-1:0] n_i4 = feat_i;
    wire signed [SAMPLE_WIDTH-1:0] n_q4 = feat_q;

    wire [15:0] n_m0 = x_m1;
    wire [15:0] n_m1 = x_m2;
    wire [15:0] n_m2 = x_m3;
    wire [15:0] n_m3 = x_m4;
    wire [15:0] n_m4 = feat_m;

    wire [15:0] n_p20 = x_p21;
    wire [15:0] n_p21 = x_p22;
    wire [15:0] n_p22 = x_p23;
    wire [15:0] n_p23 = x_p24;
    wire [15:0] n_p24 = feat_p2;
    wire [15:0] n_p30 = x_p31;
    wire [15:0] n_p31 = x_p32;
    wire [15:0] n_p32 = x_p33;
    wire [15:0] n_p33 = x_p34;
    wire [15:0] n_p34 = feat_p3;
    wire [15:0] n_p40 = x_p41;
    wire [15:0] n_p41 = x_p42;
    wire [15:0] n_p42 = x_p43;
    wire [15:0] n_p43 = x_p44;
    wire [15:0] n_p44 = feat_p4;

    wire raw_accept = enable && in_valid && in_ready;
    wire accept_sample = enable && feat_valid && (state == STATE_RUN) && coeff_loaded && can_accept_output;
    wire produce_window = accept_sample && (valid_count >= 3'd2);

    wire issue_phase0 = produce_window;
    wire issue_phase1 = (state == STATE_ISSUE1);
    wire issue_phase2 = (state == STATE_ISSUE2);
    wire issue_phase3 = (state == STATE_ISSUE3);
    wire issue_valid = issue_phase0 || issue_phase1 || issue_phase2 || issue_phase3;
    wire [1:0] issue_phase =
        issue_phase0 ? 2'd0 :
        issue_phase1 ? 2'd1 :
        issue_phase2 ? 2'd2 : 2'd3;
    wire issue_slot = issue_phase0 ? next_slot : active_slot;
    wire issue_uses_new = issue_phase0;

    wire signed [SAMPLE_WIDTH-1:0] issue_i0 = issue_uses_new ? n_i0 : w_i0;
    wire signed [SAMPLE_WIDTH-1:0] issue_q0 = issue_uses_new ? n_q0 : w_q0;
    wire signed [SAMPLE_WIDTH-1:0] issue_i1 = issue_uses_new ? n_i1 : w_i1;
    wire signed [SAMPLE_WIDTH-1:0] issue_q1 = issue_uses_new ? n_q1 : w_q1;
    wire signed [SAMPLE_WIDTH-1:0] issue_i2 = issue_uses_new ? n_i2 : w_i2;
    wire signed [SAMPLE_WIDTH-1:0] issue_q2 = issue_uses_new ? n_q2 : w_q2;
    wire signed [SAMPLE_WIDTH-1:0] issue_i3 = issue_uses_new ? n_i3 : w_i3;
    wire signed [SAMPLE_WIDTH-1:0] issue_q3 = issue_uses_new ? n_q3 : w_q3;
    wire signed [SAMPLE_WIDTH-1:0] issue_i4 = issue_uses_new ? n_i4 : w_i4;
    wire signed [SAMPLE_WIDTH-1:0] issue_q4 = issue_uses_new ? n_q4 : w_q4;

    wire [15:0] issue_m0 = issue_uses_new ? n_m0 : w_m0;
    wire [15:0] issue_m1 = issue_uses_new ? n_m1 : w_m1;
    wire [15:0] issue_m2 = issue_uses_new ? n_m2 : w_m2;
    wire [15:0] issue_m3 = issue_uses_new ? n_m3 : w_m3;
    wire [15:0] issue_m4 = issue_uses_new ? n_m4 : w_m4;
    wire [15:0] issue_p20 = issue_uses_new ? n_p20 : w_p20;
    wire [15:0] issue_p21 = issue_uses_new ? n_p21 : w_p21;
    wire [15:0] issue_p22 = issue_uses_new ? n_p22 : w_p22;
    wire [15:0] issue_p23 = issue_uses_new ? n_p23 : w_p23;
    wire [15:0] issue_p24 = issue_uses_new ? n_p24 : w_p24;
    wire [15:0] issue_p30 = issue_uses_new ? n_p30 : w_p30;
    wire [15:0] issue_p31 = issue_uses_new ? n_p31 : w_p31;
    wire [15:0] issue_p32 = issue_uses_new ? n_p32 : w_p32;
    wire [15:0] issue_p33 = issue_uses_new ? n_p33 : w_p33;
    wire [15:0] issue_p34 = issue_uses_new ? n_p34 : w_p34;
    wire [15:0] issue_p40 = issue_uses_new ? n_p40 : w_p40;
    wire [15:0] issue_p41 = issue_uses_new ? n_p41 : w_p41;
    wire [15:0] issue_p42 = issue_uses_new ? n_p42 : w_p42;
    wire [15:0] issue_p43 = issue_uses_new ? n_p43 : w_p43;
    wire [15:0] issue_p44 = issue_uses_new ? n_p44 : w_p44;

    wire [LANES-1:0] lane_valid_o;
    wire [LANES-1:0] lane_slot_o;
    wire [2*LANES-1:0] lane_phase_o;
    wire signed [47:0] lane_term_i [0:LANES-1];
    wire signed [47:0] lane_term_q [0:LANES-1];

    wire signed [47:0] lane_sum_i =
        (((lane_term_i[0] + lane_term_i[1]) + (lane_term_i[2] + lane_term_i[3])) +
         ((lane_term_i[4] + lane_term_i[5]) + (lane_term_i[6] + lane_term_i[7]))) +
        (lane_term_i[8] + lane_term_i[9]);

    wire signed [47:0] lane_sum_q =
        (((lane_term_q[0] + lane_term_q[1]) + (lane_term_q[2] + lane_term_q[3])) +
         ((lane_term_q[4] + lane_term_q[5]) + (lane_term_q[6] + lane_term_q[7]))) +
        (lane_term_q[8] + lane_term_q[9]);

    wire lane_result_valid = (lane_valid_o === {LANES{1'b1}});
    wire lane_result_slot = lane_slot_o[0];
    wire [1:0] lane_result_phase = lane_phase_o[1:0];
    wire signed [47:0] acc_next_i =
        (lane_result_phase == 2'd0) ? lane_sum_i : (acc_i[lane_result_slot] + lane_sum_i);
    wire signed [47:0] acc_next_q =
        (lane_result_phase == 2'd0) ? lane_sum_q : (acc_q[lane_result_slot] + lane_sum_q);

    genvar g;
    generate
        for (g = 0; g < LANES; g = g + 1) begin : gen_lanes
            localparam [5:0] LANE_ID = g;
            wire [5:0] term_idx = ({4'd0, issue_phase} * LANES_SIZED) + LANE_ID;
            wire signed [COEF_WIDTH-1:0] lane_coef_r =
                (term_idx < N_TERMS_SIZED) ? coef_real[term_idx] : {COEF_WIDTH{1'b0}};
            wire signed [COEF_WIDTH-1:0] lane_coef_i =
                (term_idx < N_TERMS_SIZED) ? coef_imag[term_idx] : {COEF_WIDTH{1'b0}};

            gmp_mac_lane #(
                .SAMPLE_WIDTH(SAMPLE_WIDTH),
                .COEF_WIDTH(COEF_WIDTH)
            ) lane (
                .clk(clk),
                .resetn(resetn),
                .valid_i(issue_valid),
                .slot_i(issue_slot),
                .phase_i(issue_phase),
                .term_idx_i(term_idx),
                .i0_i(issue_i0), .q0_i(issue_q0),
                .i1_i(issue_i1), .q1_i(issue_q1),
                .i2_i(issue_i2), .q2_i(issue_q2),
                .i3_i(issue_i3), .q3_i(issue_q3),
                .i4_i(issue_i4), .q4_i(issue_q4),
                .m0_i(issue_m0), .m1_i(issue_m1), .m2_i(issue_m2), .m3_i(issue_m3), .m4_i(issue_m4),
                .p20_i(issue_p20), .p21_i(issue_p21), .p22_i(issue_p22), .p23_i(issue_p23), .p24_i(issue_p24),
                .p30_i(issue_p30), .p31_i(issue_p31), .p32_i(issue_p32), .p33_i(issue_p33), .p34_i(issue_p34),
                .p40_i(issue_p40), .p41_i(issue_p41), .p42_i(issue_p42), .p43_i(issue_p43), .p44_i(issue_p44),
                .coef_real_i(lane_coef_r),
                .coef_imag_i(lane_coef_i),
                .valid_o(lane_valid_o[g]),
                .slot_o(lane_slot_o[g]),
                .phase_o(lane_phase_o[(2*g)+1:(2*g)]),
                .term_i_o(lane_term_i[g]),
                .term_q_o(lane_term_q[g])
            );
        end
    endgenerate

    integer k;

    function automatic signed [SAMPLE_WIDTH-1:0] sat16;
        input signed [47:0] value;
        begin
            if (value > 48'sd32767)
                sat16 = 16'sh7fff;
            else if (value < -48'sd32768)
                sat16 = -16'sd32768;
            else
                sat16 = value[SAMPLE_WIDTH-1:0];
        end
    endfunction

    function automatic [15:0] isqrt32;
        input [31:0] value_in;
        reg [31:0] value;
        reg [31:0] result;
        reg [31:0] bit_val;
        integer iter;
        begin
            value = value_in;
            result = 32'd0;
            bit_val = 32'h4000_0000;
            for (iter = 0; iter < 16; iter = iter + 1) begin
                if (bit_val > value)
                    bit_val = bit_val >> 2;
            end
            for (iter = 0; iter < 16; iter = iter + 1) begin
                if (bit_val != 0) begin
                    if (value >= result + bit_val) begin
                        value = value - (result + bit_val);
                        result = (result >> 1) + bit_val;
                    end else begin
                        result = result >> 1;
                    end
                    bit_val = bit_val >> 2;
                end
            end
            if (result > 32'd32767)
                isqrt32 = 16'h7fff;
            else
                isqrt32 = result[15:0];
        end
    endfunction

    function automatic [15:0] mag_q15;
        input signed [SAMPLE_WIDTH-1:0] ii;
        input signed [SAMPLE_WIDTH-1:0] qq;
        reg signed [31:0] ii_sq;
        reg signed [31:0] qq_sq;
        reg [31:0] mag2;
        begin
            ii_sq = ii * ii;
            qq_sq = qq * qq;
            mag2 = ii_sq + qq_sq;
            mag_q15 = isqrt32(mag2);
        end
    endfunction

    function automatic [15:0] q15_umult;
        input [15:0] lhs;
        input [15:0] rhs;
        reg [31:0] product;
        begin
            product = lhs * rhs;
            if ((product >>> 15) > 32'd32767)
                q15_umult = 16'h7fff;
            else
                q15_umult = (product >>> 15);
        end
    endfunction

    function automatic [31:0] mag2_from_iq;
        input signed [SAMPLE_WIDTH-1:0] ii;
        input signed [SAMPLE_WIDTH-1:0] qq;
        reg signed [31:0] ii_sq;
        reg signed [31:0] qq_sq;
        begin
            ii_sq = ii * ii;
            qq_sq = qq * qq;
            mag2_from_iq = ii_sq + qq_sq;
        end
    endfunction

    isqrt32_pipe sqrt_pipe (
        .clk(clk),
        .resetn(resetn),
        .valid_i(feat_s1_valid),
        .value_i(feat_s1_mag2),
        .valid_o(sqrt_valid),
        .root_o(sqrt_mag)
    );

    task automatic store_new_window;
        begin
            x_i0 <= n_i0; x_q0 <= n_q0; x_m0 <= n_m0;
            x_i1 <= n_i1; x_q1 <= n_q1; x_m1 <= n_m1;
            x_i2 <= n_i2; x_q2 <= n_q2; x_m2 <= n_m2;
            x_i3 <= n_i3; x_q3 <= n_q3; x_m3 <= n_m3;
            x_i4 <= n_i4; x_q4 <= n_q4; x_m4 <= n_m4;
            x_p20 <= n_p20; x_p21 <= n_p21; x_p22 <= n_p22; x_p23 <= n_p23; x_p24 <= n_p24;
            x_p30 <= n_p30; x_p31 <= n_p31; x_p32 <= n_p32; x_p33 <= n_p33; x_p34 <= n_p34;
            x_p40 <= n_p40; x_p41 <= n_p41; x_p42 <= n_p42; x_p43 <= n_p43; x_p44 <= n_p44;

            w_i0 <= n_i0; w_q0 <= n_q0; w_m0 <= n_m0;
            w_i1 <= n_i1; w_q1 <= n_q1; w_m1 <= n_m1;
            w_i2 <= n_i2; w_q2 <= n_q2; w_m2 <= n_m2;
            w_i3 <= n_i3; w_q3 <= n_q3; w_m3 <= n_m3;
            w_i4 <= n_i4; w_q4 <= n_q4; w_m4 <= n_m4;
            w_p20 <= n_p20; w_p21 <= n_p21; w_p22 <= n_p22; w_p23 <= n_p23; w_p24 <= n_p24;
            w_p30 <= n_p30; w_p31 <= n_p31; w_p32 <= n_p32; w_p33 <= n_p33; w_p34 <= n_p34;
            w_p40 <= n_p40; w_p41 <= n_p41; w_p42 <= n_p42; w_p43 <= n_p43; w_p44 <= n_p44;
        end
    endtask

    task automatic clear_windows;
        begin
            valid_count <= 3'd0;
            active_slot <= 1'b0;
            next_slot <= 1'b0;
            x_i0 <= 0; x_q0 <= 0; x_m0 <= 0;
            x_i1 <= 0; x_q1 <= 0; x_m1 <= 0;
            x_i2 <= 0; x_q2 <= 0; x_m2 <= 0;
            x_i3 <= 0; x_q3 <= 0; x_m3 <= 0;
            x_i4 <= 0; x_q4 <= 0; x_m4 <= 0;
            x_p20 <= 0; x_p21 <= 0; x_p22 <= 0; x_p23 <= 0; x_p24 <= 0;
            x_p30 <= 0; x_p31 <= 0; x_p32 <= 0; x_p33 <= 0; x_p34 <= 0;
            x_p40 <= 0; x_p41 <= 0; x_p42 <= 0; x_p43 <= 0; x_p44 <= 0;
            w_i0 <= 0; w_q0 <= 0; w_m0 <= 0;
            w_i1 <= 0; w_q1 <= 0; w_m1 <= 0;
            w_i2 <= 0; w_q2 <= 0; w_m2 <= 0;
            w_i3 <= 0; w_q3 <= 0; w_m3 <= 0;
            w_i4 <= 0; w_q4 <= 0; w_m4 <= 0;
            w_p20 <= 0; w_p21 <= 0; w_p22 <= 0; w_p23 <= 0; w_p24 <= 0;
            w_p30 <= 0; w_p31 <= 0; w_p32 <= 0; w_p33 <= 0; w_p34 <= 0;
            w_p40 <= 0; w_p41 <= 0; w_p42 <= 0; w_p43 <= 0; w_p44 <= 0;
            acc_i[0] <= 48'sd0; acc_i[1] <= 48'sd0;
            acc_q[0] <= 48'sd0; acc_q[1] <= 48'sd0;
        end
    endtask

    task automatic clear_feature_pipeline;
        integer p;
        begin
            raw_cooldown <= 2'd0;
            feat_s0_valid <= 1'b0;
            feat_s0_i <= 0;
            feat_s0_q <= 0;
            feat_s1_valid <= 1'b0;
            feat_s1_i <= 0;
            feat_s1_q <= 0;
            feat_s1_mag2 <= 32'd0;
            for (p = 0; p < 17; p = p + 1) begin
                sqrt_side_valid[p] <= 1'b0;
                sqrt_i_pipe[p] <= 0;
                sqrt_q_pipe[p] <= 0;
            end
            feat_s2_valid <= 1'b0;
            feat_s2_i <= 0;
            feat_s2_q <= 0;
            feat_s2_m <= 16'd0;
            feat_s2_p2 <= 16'd0;
            feat_s3_valid <= 1'b0;
            feat_s3_i <= 0;
            feat_s3_q <= 0;
            feat_s3_m <= 16'd0;
            feat_s3_p2 <= 16'd0;
            feat_s3_p3 <= 16'd0;
            feat_valid <= 1'b0;
            feat_i <= 0;
            feat_q <= 0;
            feat_m <= 16'd0;
            feat_p2 <= 16'd0;
            feat_p3 <= 16'd0;
            feat_p4 <= 16'd0;
        end
    endtask

    task automatic advance_feature_pipeline;
        integer p;
        begin
            if (!enable || !coeff_loaded) begin
                raw_cooldown <= 2'd0;
            end else if (raw_accept) begin
                raw_cooldown <= 2'd3;
            end else if (raw_cooldown != 2'd0) begin
                raw_cooldown <= raw_cooldown - 1'b1;
            end

            feat_s0_valid <= raw_accept;
            feat_s0_i <= raw_accept ? i_in : 0;
            feat_s0_q <= raw_accept ? q_in : 0;

            feat_s1_valid <= feat_s0_valid;
            feat_s1_i <= feat_s0_i;
            feat_s1_q <= feat_s0_q;
            feat_s1_mag2 <= mag2_from_iq(feat_s0_i, feat_s0_q);

            sqrt_side_valid[0] <= feat_s1_valid;
            sqrt_i_pipe[0] <= feat_s1_i;
            sqrt_q_pipe[0] <= feat_s1_q;
            for (p = 1; p < 17; p = p + 1) begin
                sqrt_side_valid[p] <= sqrt_side_valid[p-1];
                sqrt_i_pipe[p] <= sqrt_i_pipe[p-1];
                sqrt_q_pipe[p] <= sqrt_q_pipe[p-1];
            end

            feat_s2_valid <= sqrt_valid && sqrt_side_valid[16];
            feat_s2_i <= sqrt_i_pipe[16];
            feat_s2_q <= sqrt_q_pipe[16];
            feat_s2_m <= sqrt_mag;
            feat_s2_p2 <= q15_umult(sqrt_mag, sqrt_mag);

            feat_s3_valid <= feat_s2_valid;
            feat_s3_i <= feat_s2_i;
            feat_s3_q <= feat_s2_q;
            feat_s3_m <= feat_s2_m;
            feat_s3_p2 <= feat_s2_p2;
            feat_s3_p3 <= q15_umult(feat_s2_p2, feat_s2_m);

            feat_valid <= feat_s3_valid;
            feat_i <= feat_s3_i;
            feat_q <= feat_s3_q;
            feat_m <= feat_s3_m;
            feat_p2 <= feat_s3_p2;
            feat_p3 <= feat_s3_p3;
            feat_p4 <= q15_umult(feat_s3_p3, feat_s3_m);
        end
    endtask

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state <= STATE_LOAD;
            coeff_loaded <= 1'b0;
            load_addr <= {COEF_ADDR_WIDTH{1'b0}};
            coef_addr <= {COEF_ADDR_WIDTH{1'b0}};
            i_out <= 0;
            q_out <= 0;
            out_valid <= 1'b0;
            clear_windows();
            clear_feature_pipeline();
        end else begin
            advance_feature_pipeline();

            if (out_valid && out_ready)
                out_valid <= 1'b0;

            if (lane_result_valid) begin
                acc_i[lane_result_slot] <= acc_next_i;
                acc_q[lane_result_slot] <= acc_next_q;
                if (lane_result_phase == PHASE_LAST) begin
                    i_out <= sat16(acc_next_i);
                    q_out <= sat16(acc_next_q);
                    out_valid <= 1'b1;
                end
            end

            if (reload_coeffs) begin
                state <= STATE_LOAD;
                coeff_loaded <= 1'b0;
                load_addr <= {COEF_ADDR_WIDTH{1'b0}};
                coef_addr <= {COEF_ADDR_WIDTH{1'b0}};
                clear_windows();
                clear_feature_pipeline();
            end else begin
                case (state)
                    STATE_LOAD: begin
                        if (load_addr[0])
                            coef_imag[load_addr[COEF_ADDR_WIDTH-1:1]] <= coef_data;
                        else
                            coef_real[load_addr[COEF_ADDR_WIDTH-1:1]] <= coef_data;

                        if (load_addr == N_COEF_WORDS-1) begin
                            state <= STATE_RUN;
                            coeff_loaded <= 1'b1;
                            clear_windows();
                            clear_feature_pipeline();
                            load_addr <= {COEF_ADDR_WIDTH{1'b0}};
                            coef_addr <= {COEF_ADDR_WIDTH{1'b0}};
                        end else begin
                            load_addr <= load_addr + 1'b1;
                            coef_addr <= load_addr + 1'b1;
                        end
                    end

                    STATE_RUN: begin
                        if (!enable && in_valid && in_ready) begin
                            i_out <= i_in;
                            q_out <= q_in;
                            out_valid <= 1'b1;
                        end else if (accept_sample) begin
                            store_new_window();
                            if (valid_count < 3'd5)
                                valid_count <= valid_count + 1'b1;

                            if (produce_window) begin
                                acc_i[next_slot] <= 48'sd0;
                                acc_q[next_slot] <= 48'sd0;
                                active_slot <= next_slot;
                                next_slot <= ~next_slot;
                                state <= STATE_ISSUE1;
                            end
                        end
                    end

                    STATE_ISSUE1: state <= STATE_ISSUE2;
                    STATE_ISSUE2: state <= STATE_ISSUE3;
                    STATE_ISSUE3: state <= STATE_RUN;

                    default: begin
                        state <= STATE_LOAD;
                    end
                endcase
            end
        end
    end
endmodule
