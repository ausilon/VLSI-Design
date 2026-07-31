// ============================================================
// mac_engine.v - Maximally serialized slow-path GMP trainer
//
// OpenLane-only area-oriented snapshot:
//   - preserves the rtl_v2 mac_engine external interface
//   - keeps 39 GMP terms, complex Q2.16 coefficients and Q1.15 samples
//   - processes one basis term per cycle
//   - calculates model error over 39 cycles per captured sample
//   - accumulates NLMS numerator/denominator over another 39 cycles
//
// Training-time estimate at 100 MHz, CAPTURE_ADDR_WIDTH=10:
//   per valid sample: ~80 cycles
//   1024 samples * 20 epochs: ~1.64 M cycles = ~16.4 ms
//   coefficient division/update overhead: ~0.13 M cycles
//   This leaves orders of magnitude of margin against a 5 minute target.
// ============================================================
module mac_engine #(
    parameter SAMPLE_WIDTH = 16,
    parameter COEF_WIDTH = 18,
    parameter COEF_ADDR_WIDTH = 7,
    parameter CAPTURE_ADDR_WIDTH = 10,
    parameter TRAIN_COUNT_WIDTH = 10
)(
    input  wire clk,
    input  wire resetn,

    input  wire train_start,
    input  wire capture_done,
    input  wire [TRAIN_COUNT_WIDTH-1:0] train_sample_count,

    output reg  capture_lock,
    output reg  capture_release,
    output reg  mac_rd_en,
    output reg  [CAPTURE_ADDR_WIDTH-1:0] mac_rd_addr,
    input  wire [4*SAMPLE_WIDTH-1:0] mac_rd_data,

    output reg  train_busy,
    output reg  train_done,
    output reg  train_error,
    output reg  coef_ready,

    output reg  coef_we,
    output reg  [COEF_ADDR_WIDTH-1:0] coef_addr,
    output reg  signed [COEF_WIDTH-1:0] coef_wdata,

    output reg  [31:0] status_error_acc
);
    localparam N_GMP_TERMS = 39;
    localparam ACC_WIDTH = 64;
    localparam DIV_WIDTH = ACC_WIDTH + 16;
    localparam NLMS_MU_SHIFT = 2;
    localparam [ACC_WIDTH-1:0] NLMS_EPSILON = {{(ACC_WIDTH-1){1'b0}}, 1'b1};
    localparam [4:0] NLMS_MAX_EPOCHS = 5'd20;
    localparam [4:0] NLMS_MIN_EPOCHS = 5'd10;

    localparam STATE_IDLE           = 5'd0;
    localparam STATE_READ           = 5'd1;
    localparam STATE_LATCH          = 5'd2;
    localparam STATE_MODEL          = 5'd3;
    localparam STATE_MODEL_DONE     = 5'd4;
    localparam STATE_ACCUM_TERM     = 5'd5;
    localparam STATE_NEXT_SAMPLE    = 5'd6;
    localparam STATE_DIV_REAL_START = 5'd7;
    localparam STATE_DIV_REAL_RUN   = 5'd8;
    localparam STATE_DIV_IMAG_START = 5'd9;
    localparam STATE_DIV_IMAG_RUN   = 5'd10;
    localparam STATE_UPDATE_REAL    = 5'd11;
    localparam STATE_UPDATE_IMAG    = 5'd12;
    localparam STATE_EPOCH_DECIDE   = 5'd13;
    localparam STATE_COPY_BEST      = 5'd14;
    localparam STATE_NEXT_EPOCH     = 5'd15;
    localparam STATE_WRITE_REAL     = 5'd16;
    localparam STATE_WRITE_IMAG     = 5'd17;
    localparam STATE_DONE           = 5'd18;
    localparam STATE_ERROR          = 5'd19;
    localparam STATE_FEATURE_INIT   = 5'd20;
    localparam STATE_FEATURE_SQRT   = 5'd21;
    localparam STATE_FEATURE_P2     = 5'd22;
    localparam STATE_FEATURE_P3     = 5'd23;
    localparam STATE_FEATURE_P4     = 5'd24;
    localparam STATE_FEATURE_SHIFT  = 5'd25;
    localparam STATE_MODEL_MUL      = 5'd26;
    localparam STATE_MODEL_COMB     = 5'd27;
    localparam STATE_MODEL_ACC      = 5'd28;
    localparam STATE_ACCUM_MUL      = 5'd29;
    localparam STATE_ACCUM_COMB     = 5'd30;
    localparam STATE_ACCUM_WRITE    = 5'd31;

    reg [4:0] state;
    reg [TRAIN_COUNT_WIDTH-1:0] sample_count;
    reg [2:0] valid_count;
    reg [5:0] term_idx;
    reg [5:0] copy_idx;
    reg [4:0] epoch_count;
    reg [1:0] read_wait_count;
    reg have_best;
    reg stop_after_copy;

    reg signed [ACC_WIDTH-1:0] acc_num_real [0:N_GMP_TERMS-1];
    reg signed [ACC_WIDTH-1:0] acc_num_imag [0:N_GMP_TERMS-1];
    reg [ACC_WIDTH-1:0] acc_den [0:N_GMP_TERMS-1];
    reg [ACC_WIDTH-1:0] epoch_model_error_acc;
    reg [ACC_WIDTH-1:0] best_model_error_acc;

    reg signed [COEF_WIDTH-1:0] coef_real_est;
    reg signed [COEF_WIDTH-1:0] coef_imag_est;
    reg signed [COEF_WIDTH-1:0] coef_real_cur [0:N_GMP_TERMS-1];
    reg signed [COEF_WIDTH-1:0] coef_imag_cur [0:N_GMP_TERMS-1];
    reg signed [COEF_WIDTH-1:0] coef_real_best [0:N_GMP_TERMS-1];
    reg signed [COEF_WIDTH-1:0] coef_imag_best [0:N_GMP_TERMS-1];

    reg [DIV_WIDTH-1:0] div_dividend;
    reg [DIV_WIDTH-1:0] div_divisor;
    reg [DIV_WIDTH-1:0] div_remainder;
    reg [DIV_WIDTH-1:0] div_quotient;
    reg [6:0] div_count;
    reg div_sign;

    reg signed [SAMPLE_WIDTH-1:0] fb_i0, fb_q0;
    reg signed [SAMPLE_WIDTH-1:0] fb_i1, fb_q1;
    reg signed [SAMPLE_WIDTH-1:0] fb_i2, fb_q2;
    reg signed [SAMPLE_WIDTH-1:0] fb_i3, fb_q3;
    reg signed [SAMPLE_WIDTH-1:0] fb_i4, fb_q4;
    reg [15:0] fb_m0, fb_m1, fb_m2, fb_m3, fb_m4;
    reg [15:0] fb_p20, fb_p21, fb_p22, fb_p23, fb_p24;
    reg [15:0] fb_p30, fb_p31, fb_p32, fb_p33, fb_p34;
    reg [15:0] fb_p40, fb_p41, fb_p42, fb_p43, fb_p44;

    reg signed [SAMPLE_WIDTH-1:0] ref_i0, ref_q0;
    reg signed [SAMPLE_WIDTH-1:0] ref_i1, ref_q1;
    reg signed [SAMPLE_WIDTH-1:0] ref_i2, ref_q2;
    reg signed [SAMPLE_WIDTH-1:0] ref_i3, ref_q3;
    reg signed [SAMPLE_WIDTH-1:0] ref_i4, ref_q4;

    reg signed [47:0] model_acc_i;
    reg signed [47:0] model_acc_q;
    reg signed [SAMPLE_WIDTH-1:0] model_err_i;
    reg signed [SAMPLE_WIDTH-1:0] model_err_q;

    reg signed [SAMPLE_WIDTH-1:0] snap_ref_i;
    reg signed [SAMPLE_WIDTH-1:0] snap_ref_q;
    reg signed [SAMPLE_WIDTH-1:0] snap_fb_i;
    reg signed [SAMPLE_WIDTH-1:0] snap_fb_q;
    reg [15:0] new_mag;
    reg [15:0] new_p2;
    reg [15:0] new_p3;
    reg [15:0] new_p4;

    reg [31:0] sqrt_value;
    reg [31:0] sqrt_result;
    reg [31:0] sqrt_bit;
    reg [4:0] sqrt_count;

    reg signed [47:0] basis_i_r;
    reg signed [47:0] basis_q_r;
    reg signed [SAMPLE_WIDTH-1:0] basis_comp_i_r;
    reg signed [SAMPLE_WIDTH-1:0] basis_comp_q_r;
    reg [15:0] basis_amp_pow_r;
    reg basis_linear_r;
    reg signed [65:0] model_mul_ir;
    reg signed [65:0] model_mul_qi;
    reg signed [65:0] model_mul_ii;
    reg signed [65:0] model_mul_qr;
    reg signed [47:0] model_term_i;
    reg signed [47:0] model_term_q;
    reg signed [63:0] acc_mul_ei_bi;
    reg signed [63:0] acc_mul_eq_bq;
    reg signed [63:0] acc_mul_eq_bi;
    reg signed [63:0] acc_mul_ei_bq;
    reg signed [95:0] acc_mul_bi_bi;
    reg signed [95:0] acc_mul_bq_bq;
    reg signed [ACC_WIDTH-1:0] num_real_sample_r;
    reg signed [ACC_WIDTH-1:0] num_imag_sample_r;
    reg [ACC_WIDTH-1:0] den_sample_r;

    wire signed [SAMPLE_WIDTH-1:0] rd_ref_i = mac_rd_data[(4*SAMPLE_WIDTH)-1 -: SAMPLE_WIDTH];
    wire signed [SAMPLE_WIDTH-1:0] rd_ref_q = mac_rd_data[(3*SAMPLE_WIDTH)-1 -: SAMPLE_WIDTH];
    wire signed [SAMPLE_WIDTH-1:0] rd_fb_i  = mac_rd_data[(2*SAMPLE_WIDTH)-1 -: SAMPLE_WIDTH];
    wire signed [SAMPLE_WIDTH-1:0] rd_fb_q  = mac_rd_data[(1*SAMPLE_WIDTH)-1 -: SAMPLE_WIDTH];

    wire signed [SAMPLE_WIDTH-1:0] n_fb_i0 = fb_i1;
    wire signed [SAMPLE_WIDTH-1:0] n_fb_q0 = fb_q1;
    wire signed [SAMPLE_WIDTH-1:0] n_fb_i1 = fb_i2;
    wire signed [SAMPLE_WIDTH-1:0] n_fb_q1 = fb_q2;
    wire signed [SAMPLE_WIDTH-1:0] n_fb_i2 = fb_i3;
    wire signed [SAMPLE_WIDTH-1:0] n_fb_q2 = fb_q3;
    wire signed [SAMPLE_WIDTH-1:0] n_fb_i3 = fb_i4;
    wire signed [SAMPLE_WIDTH-1:0] n_fb_q3 = fb_q4;
    wire signed [SAMPLE_WIDTH-1:0] n_fb_i4 = snap_fb_i;
    wire signed [SAMPLE_WIDTH-1:0] n_fb_q4 = snap_fb_q;

    wire signed [SAMPLE_WIDTH-1:0] n_ref_i0 = ref_i1;
    wire signed [SAMPLE_WIDTH-1:0] n_ref_q0 = ref_q1;
    wire signed [SAMPLE_WIDTH-1:0] n_ref_i1 = ref_i2;
    wire signed [SAMPLE_WIDTH-1:0] n_ref_q1 = ref_q2;
    wire signed [SAMPLE_WIDTH-1:0] n_ref_i2 = ref_i3;
    wire signed [SAMPLE_WIDTH-1:0] n_ref_q2 = ref_q3;
    wire signed [SAMPLE_WIDTH-1:0] n_ref_i3 = ref_i4;
    wire signed [SAMPLE_WIDTH-1:0] n_ref_q3 = ref_q4;
    wire signed [SAMPLE_WIDTH-1:0] n_ref_i4 = snap_ref_i;
    wire signed [SAMPLE_WIDTH-1:0] n_ref_q4 = snap_ref_q;

    wire [15:0] n_m0 = fb_m1;
    wire [15:0] n_m1 = fb_m2;
    wire [15:0] n_m2 = fb_m3;
    wire [15:0] n_m3 = fb_m4;
    wire [15:0] n_m4 = new_mag;
    wire [15:0] n_p20 = fb_p21;
    wire [15:0] n_p21 = fb_p22;
    wire [15:0] n_p22 = fb_p23;
    wire [15:0] n_p23 = fb_p24;
    wire [15:0] n_p24 = new_p2;
    wire [15:0] n_p30 = fb_p31;
    wire [15:0] n_p31 = fb_p32;
    wire [15:0] n_p32 = fb_p33;
    wire [15:0] n_p33 = fb_p34;
    wire [15:0] n_p34 = new_p3;
    wire [15:0] n_p40 = fb_p41;
    wire [15:0] n_p41 = fb_p42;
    wire [15:0] n_p42 = fb_p43;
    wire [15:0] n_p43 = fb_p44;
    wire [15:0] n_p44 = new_p4;

    wire produce_window = (valid_count >= 3'd2);

    wire signed [SAMPLE_WIDTH:0] err_i = snap_ref_i - snap_fb_i;
    wire signed [SAMPLE_WIDTH:0] err_q = snap_ref_q - snap_fb_q;
    wire [SAMPLE_WIDTH:0] abs_err_i = err_i[SAMPLE_WIDTH] ? -err_i : err_i;
    wire [SAMPLE_WIDTH:0] abs_err_q = err_q[SAMPLE_WIDTH] ? -err_q : err_q;

    wire [31:0] sqrt_trial = sqrt_result + sqrt_bit;
    wire sqrt_take = sqrt_value >= sqrt_trial;
    wire [31:0] sqrt_value_next = sqrt_take ? (sqrt_value - sqrt_trial) : sqrt_value;
    wire [31:0] sqrt_result_next = sqrt_take ? ((sqrt_result >> 1) + sqrt_bit) : (sqrt_result >> 1);
    wire [15:0] sqrt_result_sat =
        (sqrt_result_next > 32'd32767) ? 16'h7fff : sqrt_result_next[15:0];

    wire signed [48:0] ref_i2_ext = {{(49-SAMPLE_WIDTH){ref_i2[SAMPLE_WIDTH-1]}}, ref_i2};
    wire signed [48:0] ref_q2_ext = {{(49-SAMPLE_WIDTH){ref_q2[SAMPLE_WIDTH-1]}}, ref_q2};
    wire signed [48:0] model_i_ext = {model_acc_i[47], model_acc_i};
    wire signed [48:0] model_q_ext = {model_acc_q[47], model_acc_q};
    wire signed [48:0] model_err_i_ext = ref_i2_ext - model_i_ext;
    wire signed [48:0] model_err_q_ext = ref_q2_ext - model_q_ext;
    wire signed [SAMPLE_WIDTH-1:0] model_err_i_next = sat_model_error(model_err_i_ext);
    wire signed [SAMPLE_WIDTH-1:0] model_err_q_next = sat_model_error(model_err_q_ext);
    wire [SAMPLE_WIDTH-1:0] abs_model_err_i =
        model_err_i_next[SAMPLE_WIDTH-1] ? -model_err_i_next : model_err_i_next;
    wire [SAMPLE_WIDTH-1:0] abs_model_err_q =
        model_err_q_next[SAMPLE_WIDTH-1] ? -model_err_q_next : model_err_q_next;

    wire [DIV_WIDTH-1:0] div_remainder_shift =
        {div_remainder[DIV_WIDTH-2:0], div_dividend[DIV_WIDTH-1]};
    wire div_take = div_remainder_shift >= div_divisor;
    wire [DIV_WIDTH-1:0] div_remainder_next =
        div_take ? (div_remainder_shift - div_divisor) : div_remainder_shift;
    wire [DIV_WIDTH-1:0] div_quotient_next =
        {div_quotient[DIV_WIDTH-2:0], div_take};
    wire [DIV_WIDTH-1:0] div_dividend_next =
        {div_dividend[DIV_WIDTH-2:0], 1'b0};

    wire new_best = (!have_best) || (epoch_model_error_acc < best_model_error_acc);
    wire stop_training =
        (epoch_count >= NLMS_MAX_EPOCHS-1) ||
        ((!new_best) && have_best && epoch_count >= NLMS_MIN_EPOCHS &&
         epoch_model_error_acc > best_model_error_acc);

    integer k;

    function automatic signed [SAMPLE_WIDTH-1:0] sat_model_error;
        input signed [48:0] value;
        begin
            if (value > 49'sd32767)
                sat_model_error = 16'sh7fff;
            else if (value < -49'sd32768)
                sat_model_error = -16'sd32768;
            else
                sat_model_error = value[SAMPLE_WIDTH-1:0];
        end
    endfunction

    function automatic signed [COEF_WIDTH-1:0] sat_coef_add;
        input signed [COEF_WIDTH-1:0] base;
        input signed [COEF_WIDTH-1:0] delta;
        reg signed [COEF_WIDTH:0] sum;
        begin
            sum = base + delta;
            if (sum > 19'sd131071)
                sat_coef_add = 18'sd131071;
            else if (sum < -19'sd131072)
                sat_coef_add = -18'sd131072;
            else
                sat_coef_add = sum[COEF_WIDTH-1:0];
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

    function automatic [15:0] pick_amp_power;
        input [2:0] pos;
        input [2:0] power;
        begin
            case (power)
                3'd0: pick_amp_power = 16'h7fff;
                3'd1: pick_amp_power = pick_m(pos, fb_m0, fb_m1, fb_m2, fb_m3, fb_m4);
                3'd2: pick_amp_power = pick_m(pos, fb_p20, fb_p21, fb_p22, fb_p23, fb_p24);
                3'd3: pick_amp_power = pick_m(pos, fb_p30, fb_p31, fb_p32, fb_p33, fb_p34);
                default: pick_amp_power = pick_m(pos, fb_p40, fb_p41, fb_p42, fb_p43, fb_p44);
            endcase
        end
    endfunction

    function automatic [2:0] term_x_pos;
        input [5:0] idx;
        begin
            case (idx)
                6'd0, 6'd3, 6'd6, 6'd9, 6'd12, 6'd15, 6'd18, 6'd21, 6'd24, 6'd27, 6'd30, 6'd33, 6'd36: term_x_pos = 3'd0;
                6'd1, 6'd4, 6'd7, 6'd10, 6'd13, 6'd16, 6'd19, 6'd22, 6'd25, 6'd28, 6'd31, 6'd34, 6'd37: term_x_pos = 3'd1;
                default: term_x_pos = 3'd2;
            endcase
        end
    endfunction

    function automatic [2:0] term_amp_pos;
        input [5:0] idx;
        begin
            case (idx)
                6'd3, 6'd12, 6'd21, 6'd30: term_amp_pos = 3'd0;
                6'd4, 6'd6, 6'd13, 6'd15, 6'd22, 6'd24, 6'd31, 6'd33: term_amp_pos = 3'd1;
                6'd5, 6'd7, 6'd9, 6'd14, 6'd16, 6'd18, 6'd23, 6'd25, 6'd27, 6'd32, 6'd34, 6'd36: term_amp_pos = 3'd2;
                6'd8, 6'd10, 6'd17, 6'd19, 6'd26, 6'd28, 6'd35, 6'd37: term_amp_pos = 3'd3;
                6'd11, 6'd20, 6'd29, 6'd38: term_amp_pos = 3'd4;
                default: term_amp_pos = 3'd0;
            endcase
        end
    endfunction

    function automatic [2:0] term_power;
        input [5:0] idx;
        begin
            if (idx < 6'd3)
                term_power = 3'd0;
            else if (idx < 6'd12)
                term_power = 3'd1;
            else if (idx < 6'd21)
                term_power = 3'd2;
            else if (idx < 6'd30)
                term_power = 3'd3;
            else
                term_power = 3'd4;
        end
    endfunction

    function automatic signed [SAMPLE_WIDTH-1:0] pick_i;
        input [2:0] pos;
        begin
            case (pos)
                3'd0: pick_i = fb_i0;
                3'd1: pick_i = fb_i1;
                3'd2: pick_i = fb_i2;
                3'd3: pick_i = fb_i3;
                default: pick_i = fb_i4;
            endcase
        end
    endfunction

    function automatic signed [SAMPLE_WIDTH-1:0] pick_q;
        input [2:0] pos;
        begin
            case (pos)
                3'd0: pick_q = fb_q0;
                3'd1: pick_q = fb_q1;
                3'd2: pick_q = fb_q2;
                3'd3: pick_q = fb_q3;
                default: pick_q = fb_q4;
            endcase
        end
    endfunction

    function automatic [15:0] pick_m;
        input [2:0] pos;
        input [15:0] m0, m1, m2, m3, m4;
        begin
            case (pos)
                3'd0: pick_m = m0;
                3'd1: pick_m = m1;
                3'd2: pick_m = m2;
                3'd3: pick_m = m3;
                default: pick_m = m4;
            endcase
        end
    endfunction

    function automatic [ACC_WIDTH-1:0] abs_acc;
        input signed [ACC_WIDTH-1:0] value;
        begin
            abs_acc = value[ACC_WIDTH-1] ? -value : value;
        end
    endfunction

    function automatic signed [COEF_WIDTH-1:0] sat_q2_16;
        input [DIV_WIDTH-1:0] q_abs;
        input sign;
        reg signed [COEF_WIDTH:0] signed_mag;
        begin
            if (sign) begin
                if (q_abs >= {{(DIV_WIDTH-18){1'b0}}, 18'd131072}) begin
                    sat_q2_16 = {1'b1, {(COEF_WIDTH-1){1'b0}}};
                end else begin
                    signed_mag = -$signed({1'b0, q_abs[COEF_WIDTH-2:0]});
                    sat_q2_16 = signed_mag[COEF_WIDTH-1:0];
                end
            end else begin
                if (q_abs >= {{(DIV_WIDTH-17){1'b0}}, 17'd131071})
                    sat_q2_16 = {1'b0, {(COEF_WIDTH-1){1'b1}}};
                else
                    sat_q2_16 = q_abs[COEF_WIDTH-1:0];
            end
        end
    endfunction

    task automatic clear_windows;
        begin
            valid_count <= 3'd0;
            fb_i0 <= 0; fb_q0 <= 0; fb_m0 <= 0; fb_p20 <= 0; fb_p30 <= 0; fb_p40 <= 0;
            fb_i1 <= 0; fb_q1 <= 0; fb_m1 <= 0; fb_p21 <= 0; fb_p31 <= 0; fb_p41 <= 0;
            fb_i2 <= 0; fb_q2 <= 0; fb_m2 <= 0; fb_p22 <= 0; fb_p32 <= 0; fb_p42 <= 0;
            fb_i3 <= 0; fb_q3 <= 0; fb_m3 <= 0; fb_p23 <= 0; fb_p33 <= 0; fb_p43 <= 0;
            fb_i4 <= 0; fb_q4 <= 0; fb_m4 <= 0; fb_p24 <= 0; fb_p34 <= 0; fb_p44 <= 0;
            ref_i0 <= 0; ref_q0 <= 0; ref_i1 <= 0; ref_q1 <= 0; ref_i2 <= 0; ref_q2 <= 0; ref_i3 <= 0; ref_q3 <= 0; ref_i4 <= 0; ref_q4 <= 0;
        end
    endtask

    task automatic start_nlms_division;
        input signed [ACC_WIDTH-1:0] numerator;
        input [ACC_WIDTH-1:0] denominator;
        reg [ACC_WIDTH-1:0] den_norm;
        begin
            den_norm = denominator + NLMS_EPSILON;
            div_dividend <= {{(DIV_WIDTH-ACC_WIDTH){1'b0}}, abs_acc(numerator)} << 16;
            div_divisor <= {{(DIV_WIDTH-ACC_WIDTH){1'b0}}, den_norm};
            div_remainder <= {DIV_WIDTH{1'b0}};
            div_quotient <= {DIV_WIDTH{1'b0}};
            div_count <= 7'd0;
            div_sign <= numerator[ACC_WIDTH-1];
        end
    endtask

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state <= STATE_IDLE;
            sample_count <= {TRAIN_COUNT_WIDTH{1'b0}};
            term_idx <= 6'd0;
            copy_idx <= 6'd0;
            epoch_count <= 5'd0;
            read_wait_count <= 2'd0;
            have_best <= 1'b0;
            stop_after_copy <= 1'b0;
            capture_lock <= 1'b0;
            capture_release <= 1'b0;
            mac_rd_en <= 1'b0;
            mac_rd_addr <= {CAPTURE_ADDR_WIDTH{1'b0}};
            train_busy <= 1'b0;
            train_done <= 1'b0;
            train_error <= 1'b0;
            coef_ready <= 1'b0;
            coef_we <= 1'b0;
            coef_addr <= {COEF_ADDR_WIDTH{1'b0}};
            coef_wdata <= {COEF_WIDTH{1'b0}};
            status_error_acc <= 32'd0;
            epoch_model_error_acc <= {ACC_WIDTH{1'b0}};
            best_model_error_acc <= {ACC_WIDTH{1'b1}};
            coef_real_est <= {COEF_WIDTH{1'b0}};
            coef_imag_est <= {COEF_WIDTH{1'b0}};
            div_dividend <= {DIV_WIDTH{1'b0}};
            div_divisor <= {DIV_WIDTH{1'b0}};
            div_remainder <= {DIV_WIDTH{1'b0}};
            div_quotient <= {DIV_WIDTH{1'b0}};
            div_count <= 7'd0;
            div_sign <= 1'b0;
            model_acc_i <= 48'sd0;
            model_acc_q <= 48'sd0;
            model_err_i <= {SAMPLE_WIDTH{1'b0}};
            model_err_q <= {SAMPLE_WIDTH{1'b0}};
            snap_ref_i <= {SAMPLE_WIDTH{1'b0}};
            snap_ref_q <= {SAMPLE_WIDTH{1'b0}};
            snap_fb_i <= {SAMPLE_WIDTH{1'b0}};
            snap_fb_q <= {SAMPLE_WIDTH{1'b0}};
            new_mag <= 16'd0;
            new_p2 <= 16'd0;
            new_p3 <= 16'd0;
            new_p4 <= 16'd0;
            sqrt_value <= 32'd0;
            sqrt_result <= 32'd0;
            sqrt_bit <= 32'd0;
            sqrt_count <= 5'd0;
            basis_i_r <= 48'sd0;
            basis_q_r <= 48'sd0;
            basis_comp_i_r <= {SAMPLE_WIDTH{1'b0}};
            basis_comp_q_r <= {SAMPLE_WIDTH{1'b0}};
            basis_amp_pow_r <= 16'd0;
            basis_linear_r <= 1'b0;
            model_mul_ir <= 66'sd0;
            model_mul_qi <= 66'sd0;
            model_mul_ii <= 66'sd0;
            model_mul_qr <= 66'sd0;
            model_term_i <= 48'sd0;
            model_term_q <= 48'sd0;
            acc_mul_ei_bi <= 64'sd0;
            acc_mul_eq_bq <= 64'sd0;
            acc_mul_eq_bi <= 64'sd0;
            acc_mul_ei_bq <= 64'sd0;
            acc_mul_bi_bi <= 96'sd0;
            acc_mul_bq_bq <= 96'sd0;
            num_real_sample_r <= {ACC_WIDTH{1'b0}};
            num_imag_sample_r <= {ACC_WIDTH{1'b0}};
            den_sample_r <= {ACC_WIDTH{1'b0}};
            clear_windows();
            for (k = 0; k < N_GMP_TERMS; k = k + 1) begin
                acc_num_real[k] <= {ACC_WIDTH{1'b0}};
                acc_num_imag[k] <= {ACC_WIDTH{1'b0}};
                acc_den[k] <= {ACC_WIDTH{1'b0}};
                coef_real_cur[k] <= {COEF_WIDTH{1'b0}};
                coef_imag_cur[k] <= {COEF_WIDTH{1'b0}};
                coef_real_best[k] <= {COEF_WIDTH{1'b0}};
                coef_imag_best[k] <= {COEF_WIDTH{1'b0}};
            end
        end else begin
            capture_release <= 1'b0;
            mac_rd_en <= 1'b0;
            coef_we <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    train_busy <= 1'b0;
                    capture_lock <= 1'b0;
                    if (train_start) begin
                        train_done <= 1'b0;
                        train_error <= 1'b0;
                        coef_ready <= 1'b0;
                        if (capture_done && train_sample_count >= 2) begin
                            train_busy <= 1'b1;
                            capture_lock <= 1'b1;
                            sample_count <= {TRAIN_COUNT_WIDTH{1'b0}};
                            term_idx <= 6'd0;
                            epoch_count <= 5'd0;
                            have_best <= 1'b0;
                            stop_after_copy <= 1'b0;
                            mac_rd_addr <= {CAPTURE_ADDR_WIDTH{1'b0}};
                            status_error_acc <= 32'd0;
                            epoch_model_error_acc <= {ACC_WIDTH{1'b0}};
                            best_model_error_acc <= {ACC_WIDTH{1'b1}};
                            model_acc_i <= 48'sd0;
                            model_acc_q <= 48'sd0;
                            model_err_i <= {SAMPLE_WIDTH{1'b0}};
                            model_err_q <= {SAMPLE_WIDTH{1'b0}};
                            snap_ref_i <= {SAMPLE_WIDTH{1'b0}};
                            snap_ref_q <= {SAMPLE_WIDTH{1'b0}};
                            snap_fb_i <= {SAMPLE_WIDTH{1'b0}};
                            snap_fb_q <= {SAMPLE_WIDTH{1'b0}};
                            new_mag <= 16'd0;
                            new_p2 <= 16'd0;
                            new_p3 <= 16'd0;
                            new_p4 <= 16'd0;
                            sqrt_value <= 32'd0;
                            sqrt_result <= 32'd0;
                            sqrt_bit <= 32'd0;
                            sqrt_count <= 5'd0;
                            basis_i_r <= 48'sd0;
                            basis_q_r <= 48'sd0;
                            basis_comp_i_r <= {SAMPLE_WIDTH{1'b0}};
                            basis_comp_q_r <= {SAMPLE_WIDTH{1'b0}};
                            basis_amp_pow_r <= 16'd0;
                            basis_linear_r <= 1'b0;
                            model_mul_ir <= 66'sd0;
                            model_mul_qi <= 66'sd0;
                            model_mul_ii <= 66'sd0;
                            model_mul_qr <= 66'sd0;
                            model_term_i <= 48'sd0;
                            model_term_q <= 48'sd0;
                            acc_mul_ei_bi <= 64'sd0;
                            acc_mul_eq_bq <= 64'sd0;
                            acc_mul_eq_bi <= 64'sd0;
                            acc_mul_ei_bq <= 64'sd0;
                            acc_mul_bi_bi <= 96'sd0;
                            acc_mul_bq_bq <= 96'sd0;
                            num_real_sample_r <= {ACC_WIDTH{1'b0}};
                            num_imag_sample_r <= {ACC_WIDTH{1'b0}};
                            den_sample_r <= {ACC_WIDTH{1'b0}};
                            clear_windows();
                            for (k = 0; k < N_GMP_TERMS; k = k + 1) begin
                                acc_num_real[k] <= {ACC_WIDTH{1'b0}};
                                acc_num_imag[k] <= {ACC_WIDTH{1'b0}};
                                acc_den[k] <= {ACC_WIDTH{1'b0}};
                                coef_real_cur[k] <= {COEF_WIDTH{1'b0}};
                                coef_imag_cur[k] <= {COEF_WIDTH{1'b0}};
                                coef_real_best[k] <= {COEF_WIDTH{1'b0}};
                                coef_imag_best[k] <= {COEF_WIDTH{1'b0}};
                            end
                            state <= STATE_READ;
                        end else begin
                            train_error <= 1'b1;
                            state <= STATE_ERROR;
                        end
                    end
                end

                STATE_READ: begin
                    train_busy <= 1'b1;
                    capture_lock <= 1'b1;
                    mac_rd_en <= 1'b1;
                    read_wait_count <= 2'd2;
                    state <= STATE_LATCH;
                end

                STATE_LATCH: begin
                    train_busy <= 1'b1;
                    capture_lock <= 1'b1;
                    if (read_wait_count != 2'd0) begin
                        read_wait_count <= read_wait_count - 1'b1;
                    end else begin
                        mac_rd_en <= 1'b0;
                        snap_ref_i <= rd_ref_i;
                        snap_ref_q <= rd_ref_q;
                        snap_fb_i <= rd_fb_i;
                        snap_fb_q <= rd_fb_q;
                        state <= STATE_FEATURE_INIT;
                    end
                end

                STATE_FEATURE_INIT: begin
                    train_busy <= 1'b1;
                    capture_lock <= 1'b1;
                    status_error_acc <= status_error_acc + abs_err_i + abs_err_q;
                    sqrt_value <= (snap_fb_i * snap_fb_i) + (snap_fb_q * snap_fb_q);
                    sqrt_result <= 32'd0;
                    sqrt_bit <= 32'h4000_0000;
                    sqrt_count <= 5'd0;
                    state <= STATE_FEATURE_SQRT;
                end

                STATE_FEATURE_SQRT: begin
                    train_busy <= 1'b1;
                    capture_lock <= 1'b1;
                    sqrt_value <= sqrt_value_next;
                    sqrt_result <= sqrt_result_next;
                    sqrt_bit <= sqrt_bit >> 2;
                    if (sqrt_count == 5'd15) begin
                        new_mag <= sqrt_result_sat;
                        state <= STATE_FEATURE_P2;
                    end else begin
                        sqrt_count <= sqrt_count + 1'b1;
                    end
                end

                STATE_FEATURE_P2: begin
                    train_busy <= 1'b1;
                    capture_lock <= 1'b1;
                    new_p2 <= q15_umult(new_mag, new_mag);
                    state <= STATE_FEATURE_P3;
                end

                STATE_FEATURE_P3: begin
                    train_busy <= 1'b1;
                    capture_lock <= 1'b1;
                    new_p3 <= q15_umult(new_p2, new_mag);
                    state <= STATE_FEATURE_P4;
                end

                STATE_FEATURE_P4: begin
                    train_busy <= 1'b1;
                    capture_lock <= 1'b1;
                    new_p4 <= q15_umult(new_p3, new_mag);
                    state <= STATE_FEATURE_SHIFT;
                end

                STATE_FEATURE_SHIFT: begin
                    train_busy <= 1'b1;
                    capture_lock <= 1'b1;
                    fb_i0 <= n_fb_i0; fb_q0 <= n_fb_q0; fb_m0 <= n_m0; fb_p20 <= n_p20; fb_p30 <= n_p30; fb_p40 <= n_p40;
                    fb_i1 <= n_fb_i1; fb_q1 <= n_fb_q1; fb_m1 <= n_m1; fb_p21 <= n_p21; fb_p31 <= n_p31; fb_p41 <= n_p41;
                    fb_i2 <= n_fb_i2; fb_q2 <= n_fb_q2; fb_m2 <= n_m2; fb_p22 <= n_p22; fb_p32 <= n_p32; fb_p42 <= n_p42;
                    fb_i3 <= n_fb_i3; fb_q3 <= n_fb_q3; fb_m3 <= n_m3; fb_p23 <= n_p23; fb_p33 <= n_p33; fb_p43 <= n_p43;
                    fb_i4 <= n_fb_i4; fb_q4 <= n_fb_q4; fb_m4 <= n_m4; fb_p24 <= n_p24; fb_p34 <= n_p34; fb_p44 <= n_p44;
                    ref_i0 <= n_ref_i0; ref_q0 <= n_ref_q0;
                    ref_i1 <= n_ref_i1; ref_q1 <= n_ref_q1;
                    ref_i2 <= n_ref_i2; ref_q2 <= n_ref_q2;
                    ref_i3 <= n_ref_i3; ref_q3 <= n_ref_q3;
                    ref_i4 <= n_ref_i4; ref_q4 <= n_ref_q4;
                    if (valid_count < 3'd5)
                        valid_count <= valid_count + 1'b1;

                    if (produce_window) begin
                        term_idx <= 6'd0;
                        model_acc_i <= 48'sd0;
                        model_acc_q <= 48'sd0;
                        state <= STATE_MODEL;
                    end else begin
                        state <= STATE_NEXT_SAMPLE;
                    end
                end

                STATE_MODEL: begin
                    train_busy <= 1'b1;
                    capture_lock <= 1'b1;
                    basis_comp_i_r <= pick_i(term_x_pos(term_idx));
                    basis_comp_q_r <= pick_q(term_x_pos(term_idx));
                    basis_amp_pow_r <= pick_amp_power(term_amp_pos(term_idx), term_power(term_idx));
                    basis_linear_r <= (term_power(term_idx) == 3'd0);
                    state <= STATE_MODEL_MUL;
                end

                STATE_MODEL_MUL: begin
                    train_busy <= 1'b1;
                    capture_lock <= 1'b1;
                    if (basis_linear_r) begin
                        basis_i_r <= {{(48-SAMPLE_WIDTH){basis_comp_i_r[SAMPLE_WIDTH-1]}}, basis_comp_i_r};
                        basis_q_r <= {{(48-SAMPLE_WIDTH){basis_comp_q_r[SAMPLE_WIDTH-1]}}, basis_comp_q_r};
                    end else begin
                        basis_i_r <= (basis_comp_i_r * $signed({1'b0, basis_amp_pow_r})) >>> 15;
                        basis_q_r <= (basis_comp_q_r * $signed({1'b0, basis_amp_pow_r})) >>> 15;
                    end
                    state <= STATE_MODEL_COMB;
                end

                STATE_MODEL_COMB: begin
                    train_busy <= 1'b1;
                    capture_lock <= 1'b1;
                    model_mul_ir <= basis_i_r * coef_real_cur[term_idx];
                    model_mul_qi <= basis_q_r * coef_imag_cur[term_idx];
                    model_mul_ii <= basis_i_r * coef_imag_cur[term_idx];
                    model_mul_qr <= basis_q_r * coef_real_cur[term_idx];
                    state <= STATE_MODEL_ACC;
                end

                STATE_MODEL_ACC: begin
                    train_busy <= 1'b1;
                    capture_lock <= 1'b1;
                    model_term_i <= (model_mul_ir - model_mul_qi) >>> 16;
                    model_term_q <= (model_mul_ii + model_mul_qr) >>> 16;
                    model_acc_i <= model_acc_i + ((model_mul_ir - model_mul_qi) >>> 16);
                    model_acc_q <= model_acc_q + ((model_mul_ii + model_mul_qr) >>> 16);
                    if (term_idx == N_GMP_TERMS-1) begin
                        state <= STATE_MODEL_DONE;
                    end else begin
                        term_idx <= term_idx + 1'b1;
                        state <= STATE_MODEL;
                    end
                end

                STATE_MODEL_DONE: begin
                    train_busy <= 1'b1;
                    capture_lock <= 1'b1;
                    model_err_i <= model_err_i_next;
                    model_err_q <= model_err_q_next;
                    epoch_model_error_acc <= epoch_model_error_acc + abs_model_err_i + abs_model_err_q;
                    term_idx <= 6'd0;
                    state <= STATE_ACCUM_TERM;
                end

                STATE_ACCUM_TERM: begin
                    train_busy <= 1'b1;
                    capture_lock <= 1'b1;
                    basis_comp_i_r <= pick_i(term_x_pos(term_idx));
                    basis_comp_q_r <= pick_q(term_x_pos(term_idx));
                    basis_amp_pow_r <= pick_amp_power(term_amp_pos(term_idx), term_power(term_idx));
                    basis_linear_r <= (term_power(term_idx) == 3'd0);
                    state <= STATE_ACCUM_MUL;
                end

                STATE_ACCUM_MUL: begin
                    train_busy <= 1'b1;
                    capture_lock <= 1'b1;
                    if (basis_linear_r) begin
                        basis_i_r <= {{(48-SAMPLE_WIDTH){basis_comp_i_r[SAMPLE_WIDTH-1]}}, basis_comp_i_r};
                        basis_q_r <= {{(48-SAMPLE_WIDTH){basis_comp_q_r[SAMPLE_WIDTH-1]}}, basis_comp_q_r};
                    end else begin
                        basis_i_r <= (basis_comp_i_r * $signed({1'b0, basis_amp_pow_r})) >>> 15;
                        basis_q_r <= (basis_comp_q_r * $signed({1'b0, basis_amp_pow_r})) >>> 15;
                    end
                    state <= STATE_ACCUM_COMB;
                end

                STATE_ACCUM_COMB: begin
                    train_busy <= 1'b1;
                    capture_lock <= 1'b1;
                    acc_mul_ei_bi <= model_err_i * basis_i_r;
                    acc_mul_eq_bq <= model_err_q * basis_q_r;
                    acc_mul_eq_bi <= model_err_q * basis_i_r;
                    acc_mul_ei_bq <= model_err_i * basis_q_r;
                    acc_mul_bi_bi <= basis_i_r * basis_i_r;
                    acc_mul_bq_bq <= basis_q_r * basis_q_r;
                    state <= STATE_ACCUM_WRITE;
                end

                STATE_ACCUM_WRITE: begin
                    train_busy <= 1'b1;
                    capture_lock <= 1'b1;
                    num_real_sample_r <= acc_mul_ei_bi + acc_mul_eq_bq;
                    num_imag_sample_r <= acc_mul_eq_bi - acc_mul_ei_bq;
                    den_sample_r <= acc_mul_bi_bi + acc_mul_bq_bq;
                    acc_num_real[term_idx] <= acc_num_real[term_idx] + (acc_mul_ei_bi + acc_mul_eq_bq);
                    acc_num_imag[term_idx] <= acc_num_imag[term_idx] + (acc_mul_eq_bi - acc_mul_ei_bq);
                    acc_den[term_idx] <= acc_den[term_idx] + (acc_mul_bi_bi + acc_mul_bq_bq);
                    if (term_idx == N_GMP_TERMS-1) begin
                        state <= STATE_NEXT_SAMPLE;
                    end else begin
                        term_idx <= term_idx + 1'b1;
                        state <= STATE_ACCUM_TERM;
                    end
                end

                STATE_NEXT_SAMPLE: begin
                    train_busy <= 1'b1;
                    capture_lock <= 1'b1;
                    if (sample_count >= train_sample_count) begin
                        term_idx <= 6'd0;
                        state <= STATE_DIV_REAL_START;
                    end else begin
                        sample_count <= sample_count + 1'b1;
                        mac_rd_addr <= mac_rd_addr + 1'b1;
                        state <= STATE_READ;
                    end
                end

                STATE_DIV_REAL_START: begin
                    train_busy <= 1'b1;
                    capture_lock <= 1'b1;
                    if (acc_den[term_idx] == {ACC_WIDTH{1'b0}}) begin
                        coef_real_est <= {COEF_WIDTH{1'b0}};
                        state <= STATE_DIV_IMAG_START;
                    end else begin
                        start_nlms_division(acc_num_real[term_idx], acc_den[term_idx]);
                        state <= STATE_DIV_REAL_RUN;
                    end
                end

                STATE_DIV_REAL_RUN: begin
                    train_busy <= 1'b1;
                    capture_lock <= 1'b1;
                    div_remainder <= div_remainder_next;
                    div_quotient <= div_quotient_next;
                    div_dividend <= div_dividend_next;
                    if (div_count == DIV_WIDTH-1) begin
                        coef_real_est <= sat_q2_16(div_quotient_next >> NLMS_MU_SHIFT, div_sign);
                        state <= STATE_DIV_IMAG_START;
                    end else begin
                        div_count <= div_count + 1'b1;
                    end
                end

                STATE_DIV_IMAG_START: begin
                    train_busy <= 1'b1;
                    capture_lock <= 1'b1;
                    if (acc_den[term_idx] == {ACC_WIDTH{1'b0}}) begin
                        coef_imag_est <= {COEF_WIDTH{1'b0}};
                        state <= STATE_UPDATE_REAL;
                    end else begin
                        start_nlms_division(acc_num_imag[term_idx], acc_den[term_idx]);
                        state <= STATE_DIV_IMAG_RUN;
                    end
                end

                STATE_DIV_IMAG_RUN: begin
                    train_busy <= 1'b1;
                    capture_lock <= 1'b1;
                    div_remainder <= div_remainder_next;
                    div_quotient <= div_quotient_next;
                    div_dividend <= div_dividend_next;
                    if (div_count == DIV_WIDTH-1) begin
                        coef_imag_est <= sat_q2_16(div_quotient_next >> NLMS_MU_SHIFT, div_sign);
                        state <= STATE_UPDATE_REAL;
                    end else begin
                        div_count <= div_count + 1'b1;
                    end
                end

                STATE_UPDATE_REAL: begin
                    train_busy <= 1'b1;
                    capture_lock <= 1'b1;
                    coef_real_cur[term_idx] <= sat_coef_add(coef_real_cur[term_idx], coef_real_est);
                    state <= STATE_UPDATE_IMAG;
                end

                STATE_UPDATE_IMAG: begin
                    train_busy <= 1'b1;
                    capture_lock <= 1'b1;
                    coef_imag_cur[term_idx] <= sat_coef_add(coef_imag_cur[term_idx], coef_imag_est);
                    if (term_idx == N_GMP_TERMS-1) begin
                        state <= STATE_EPOCH_DECIDE;
                    end else begin
                        term_idx <= term_idx + 1'b1;
                        state <= STATE_DIV_REAL_START;
                    end
                end

                STATE_EPOCH_DECIDE: begin
                    train_busy <= 1'b1;
                    capture_lock <= 1'b1;
                    stop_after_copy <= stop_training;
                    if (new_best) begin
                        have_best <= 1'b1;
                        best_model_error_acc <= epoch_model_error_acc;
                        copy_idx <= 6'd0;
                        state <= STATE_COPY_BEST;
                    end else if (stop_training) begin
                        term_idx <= 6'd0;
                        state <= STATE_WRITE_REAL;
                    end else begin
                        state <= STATE_NEXT_EPOCH;
                    end
                end

                STATE_COPY_BEST: begin
                    train_busy <= 1'b1;
                    capture_lock <= 1'b1;
                    coef_real_best[copy_idx] <= coef_real_cur[copy_idx];
                    coef_imag_best[copy_idx] <= coef_imag_cur[copy_idx];
                    if (copy_idx == N_GMP_TERMS-1) begin
                        if (stop_after_copy) begin
                            term_idx <= 6'd0;
                            state <= STATE_WRITE_REAL;
                        end else begin
                            state <= STATE_NEXT_EPOCH;
                        end
                    end else begin
                        copy_idx <= copy_idx + 1'b1;
                    end
                end

                STATE_NEXT_EPOCH: begin
                    train_busy <= 1'b1;
                    capture_lock <= 1'b1;
                    epoch_count <= epoch_count + 1'b1;
                    sample_count <= {TRAIN_COUNT_WIDTH{1'b0}};
                    term_idx <= 6'd0;
                    mac_rd_addr <= {CAPTURE_ADDR_WIDTH{1'b0}};
                    epoch_model_error_acc <= {ACC_WIDTH{1'b0}};
                    clear_windows();
                    for (k = 0; k < N_GMP_TERMS; k = k + 1) begin
                        acc_num_real[k] <= {ACC_WIDTH{1'b0}};
                        acc_num_imag[k] <= {ACC_WIDTH{1'b0}};
                        acc_den[k] <= {ACC_WIDTH{1'b0}};
                    end
                    state <= STATE_READ;
                end

                STATE_WRITE_REAL: begin
                    train_busy <= 1'b1;
                    capture_lock <= 1'b1;
                    coef_we <= 1'b1;
                    coef_addr <= {term_idx, 1'b0};
                    coef_wdata <= coef_real_best[term_idx];
                    state <= STATE_WRITE_IMAG;
                end

                STATE_WRITE_IMAG: begin
                    train_busy <= 1'b1;
                    capture_lock <= 1'b1;
                    coef_we <= 1'b1;
                    coef_addr <= {term_idx, 1'b1};
                    coef_wdata <= coef_imag_best[term_idx];
                    if (term_idx == N_GMP_TERMS-1) begin
                        state <= STATE_DONE;
                    end else begin
                        term_idx <= term_idx + 1'b1;
                        state <= STATE_WRITE_REAL;
                    end
                end

                STATE_DONE: begin
                    train_busy <= 1'b0;
                    capture_lock <= 1'b0;
                    capture_release <= 1'b1;
                    train_done <= 1'b1;
                    coef_ready <= 1'b1;
                    state <= STATE_IDLE;
                end

                STATE_ERROR: begin
                    train_busy <= 1'b0;
                    capture_lock <= 1'b0;
                    capture_release <= 1'b1;
                    train_done <= 1'b1;
                    coef_ready <= 1'b0;
                    state <= STATE_IDLE;
                end

                default: begin
                    state <= STATE_IDLE;
                end
            endcase
        end
    end
endmodule
