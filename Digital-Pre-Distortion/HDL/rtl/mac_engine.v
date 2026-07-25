// ============================================================
// mac_engine.v - Slow-path internal GMP training engine
//
// v2 final training role:
//   - lock and read a completed REF/FB capture snapshot
//   - build the same 39-term GMP basis used by gmp_engine
//   - estimate one complex coefficient for every GMP term
//   - write all 78 coefficient words to the inactive coefficient bank
//   - signal coef_ready so firmware can request a sync_event switch
//
// Training model:
//   Indirect-learning block NLMS, per GMP term:
//     w_k <- w_k + mu * sum(e * conj(phi_k)) /
//            (epsilon + sum(|phi_k|^2))
//
//   The trainer runs up to 20 epochs over the captured snapshot. It keeps the
//   best coefficient set by model-error L1 and stops early after at least 10
//   epochs if the current epoch becomes worse than the best observed epoch.
//
// This is a complete 39-term coefficient generator, but it is not yet a full
// coupled least-squares matrix solve. That choice keeps this slow path small
// and synthesizable for the first SKY130-oriented integration milestone.
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
    localparam N_COEF_WORDS = 2 * N_GMP_TERMS;
    localparam ACC_WIDTH = 64;
    localparam DIV_WIDTH = ACC_WIDTH + 16;
    localparam NLMS_MU_SHIFT = 2;
    localparam [ACC_WIDTH-1:0] NLMS_EPSILON = {{(ACC_WIDTH-1){1'b0}}, 1'b1};
    localparam [4:0] NLMS_MAX_EPOCHS = 5'd20;
    localparam [4:0] NLMS_MIN_EPOCHS = 5'd10;

    localparam STATE_IDLE            = 5'd0;
    localparam STATE_READ            = 5'd1;
    localparam STATE_ACCUM           = 5'd2;
    localparam STATE_DIV_REAL_START  = 5'd3;
    localparam STATE_DIV_REAL_RUN    = 5'd4;
    localparam STATE_DIV_IMAG_START  = 5'd5;
    localparam STATE_DIV_IMAG_RUN    = 5'd6;
    localparam STATE_UPDATE_REAL     = 5'd7;
    localparam STATE_UPDATE_IMAG     = 5'd8;
    localparam STATE_EPOCH_DONE      = 5'd9;
    localparam STATE_WRITE_BEST_REAL = 5'd10;
    localparam STATE_WRITE_BEST_IMAG = 5'd11;
    localparam STATE_DONE            = 5'd12;
    localparam STATE_ERROR           = 5'd13;

    reg [4:0] state;
    reg [TRAIN_COUNT_WIDTH-1:0] sample_count;
    reg [2:0] valid_count;
    reg [5:0] term_idx;
    reg [4:0] epoch_count;
    reg have_best;

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

    reg signed [SAMPLE_WIDTH-1:0] ref_i0, ref_q0;
    reg signed [SAMPLE_WIDTH-1:0] ref_i1, ref_q1;
    reg signed [SAMPLE_WIDTH-1:0] ref_i2, ref_q2;
    reg signed [SAMPLE_WIDTH-1:0] ref_i3, ref_q3;
    reg signed [SAMPLE_WIDTH-1:0] ref_i4, ref_q4;

    wire signed [SAMPLE_WIDTH-1:0] snap_ref_i = mac_rd_data[(4*SAMPLE_WIDTH)-1 -: SAMPLE_WIDTH];
    wire signed [SAMPLE_WIDTH-1:0] snap_ref_q = mac_rd_data[(3*SAMPLE_WIDTH)-1 -: SAMPLE_WIDTH];
    wire signed [SAMPLE_WIDTH-1:0] snap_fb_i  = mac_rd_data[(2*SAMPLE_WIDTH)-1 -: SAMPLE_WIDTH];
    wire signed [SAMPLE_WIDTH-1:0] snap_fb_q  = mac_rd_data[(1*SAMPLE_WIDTH)-1 -: SAMPLE_WIDTH];

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

    wire signed [SAMPLE_WIDTH:0] err_i = snap_ref_i - snap_fb_i;
    wire signed [SAMPLE_WIDTH:0] err_q = snap_ref_q - snap_fb_q;
    wire [SAMPLE_WIDTH:0] abs_err_i = err_i[SAMPLE_WIDTH] ? -err_i : err_i;
    wire [SAMPLE_WIDTH:0] abs_err_q = err_q[SAMPLE_WIDTH] ? -err_q : err_q;
    wire produce_window = (valid_count >= 3'd2);

    wire [15:0] n_m0 = mag_q15(n_fb_i0, n_fb_q0);
    wire [15:0] n_m1 = mag_q15(n_fb_i1, n_fb_q1);
    wire [15:0] n_m2 = mag_q15(n_fb_i2, n_fb_q2);
    wire [15:0] n_m3 = mag_q15(n_fb_i3, n_fb_q3);
    wire [15:0] n_m4 = mag_q15(n_fb_i4, n_fb_q4);

    wire signed [47:0] basis_i_now =
        basis_component(pick_i(term_x_pos(term_idx), n_fb_i0, n_fb_i1, n_fb_i2, n_fb_i3, n_fb_i4),
                        pick_m(term_amp_pos(term_idx), n_m0, n_m1, n_m2, n_m3, n_m4),
                        term_power(term_idx));
    wire signed [47:0] basis_q_now =
        basis_component(pick_q(term_x_pos(term_idx), n_fb_q0, n_fb_q1, n_fb_q2, n_fb_q3, n_fb_q4),
                        pick_m(term_amp_pos(term_idx), n_m0, n_m1, n_m2, n_m3, n_m4),
                        term_power(term_idx));

    wire signed [63:0] num_real_prod =
        (n_ref_i2 * basis_i_now) + (n_ref_q2 * basis_q_now);
    wire signed [63:0] num_imag_prod =
        (n_ref_q2 * basis_i_now) - (n_ref_i2 * basis_q_now);
    wire [63:0] den_prod =
        (basis_i_now * basis_i_now) + (basis_q_now * basis_q_now);

    wire signed [ACC_WIDTH-1:0] num_real_sample =
        {{(ACC_WIDTH-64){num_real_prod[63]}}, num_real_prod};
    wire signed [ACC_WIDTH-1:0] num_imag_sample =
        {{(ACC_WIDTH-64){num_imag_prod[63]}}, num_imag_prod};
    wire [ACC_WIDTH-1:0] den_sample =
        den_prod[ACC_WIDTH-1:0];

    wire [DIV_WIDTH-1:0] div_remainder_shift =
        {div_remainder[DIV_WIDTH-2:0], div_dividend[DIV_WIDTH-1]};
    wire div_take = div_remainder_shift >= div_divisor;
    wire [DIV_WIDTH-1:0] div_remainder_next =
        div_take ? (div_remainder_shift - div_divisor) : div_remainder_shift;
    wire [DIV_WIDTH-1:0] div_quotient_next =
        {div_quotient[DIV_WIDTH-2:0], div_take};
    wire [DIV_WIDTH-1:0] div_dividend_next =
        {div_dividend[DIV_WIDTH-2:0], 1'b0};

    wire signed [47:0] model_i_now = model_acc_i();
    wire signed [47:0] model_q_now = model_acc_q();
    wire signed [48:0] ref_i2_ext = {{(49-SAMPLE_WIDTH){n_ref_i2[SAMPLE_WIDTH-1]}}, n_ref_i2};
    wire signed [48:0] ref_q2_ext = {{(49-SAMPLE_WIDTH){n_ref_q2[SAMPLE_WIDTH-1]}}, n_ref_q2};
    wire signed [48:0] model_i_ext = {model_i_now[47], model_i_now};
    wire signed [48:0] model_q_ext = {model_q_now[47], model_q_now};
    wire signed [48:0] model_err_i_ext = ref_i2_ext - model_i_ext;
    wire signed [48:0] model_err_q_ext = ref_q2_ext - model_q_ext;
    wire signed [SAMPLE_WIDTH-1:0] model_err_i = sat_model_error(model_err_i_ext);
    wire signed [SAMPLE_WIDTH-1:0] model_err_q = sat_model_error(model_err_q_ext);
    wire [SAMPLE_WIDTH-1:0] abs_model_err_i = model_err_i[SAMPLE_WIDTH-1] ? -model_err_i : model_err_i;
    wire [SAMPLE_WIDTH-1:0] abs_model_err_q = model_err_q[SAMPLE_WIDTH-1] ? -model_err_q : model_err_q;

    integer k;

    function [15:0] isqrt32;
        input [31:0] value_in;
        reg [31:0] value;
        reg [31:0] result;
        reg [31:0] bit_val;
        begin
            value = value_in;
            result = 32'd0;
            bit_val = 32'h4000_0000;
            while (bit_val > value)
                bit_val = bit_val >> 2;
            while (bit_val != 0) begin
                if (value >= result + bit_val) begin
                    value = value - (result + bit_val);
                    result = (result >> 1) + bit_val;
                end else begin
                    result = result >> 1;
                end
                bit_val = bit_val >> 2;
            end
            if (result > 32'd32767)
                isqrt32 = 16'h7fff;
            else
                isqrt32 = result[15:0];
        end
    endfunction

    function [15:0] mag_q15;
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

    function [15:0] amp_power;
        input [15:0] amp;
        input [2:0] power;
        reg [63:0] value;
        integer p;
        begin
            if (power == 0) begin
                amp_power = 16'h7fff;
            end else begin
                value = amp;
                for (p = 1; p < power; p = p + 1)
                    value = (value * amp) >>> 15;
                if (value > 64'd32767)
                    amp_power = 16'h7fff;
                else
                    amp_power = value[15:0];
            end
        end
    endfunction

    function [2:0] term_x_pos;
        input [5:0] idx;
        begin
            case (idx)
                6'd0, 6'd3, 6'd6, 6'd9, 6'd12, 6'd15, 6'd18, 6'd21, 6'd24, 6'd27, 6'd30, 6'd33, 6'd36: term_x_pos = 3'd0;
                6'd1, 6'd4, 6'd7, 6'd10, 6'd13, 6'd16, 6'd19, 6'd22, 6'd25, 6'd28, 6'd31, 6'd34, 6'd37: term_x_pos = 3'd1;
                default: term_x_pos = 3'd2;
            endcase
        end
    endfunction

    function [2:0] term_amp_pos;
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

    function [2:0] term_power;
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

    function signed [SAMPLE_WIDTH-1:0] pick_i;
        input [2:0] pos;
        input signed [SAMPLE_WIDTH-1:0] i0, i1, i2, i3, i4;
        begin
            case (pos)
                3'd0: pick_i = i0;
                3'd1: pick_i = i1;
                3'd2: pick_i = i2;
                3'd3: pick_i = i3;
                default: pick_i = i4;
            endcase
        end
    endfunction

    function signed [SAMPLE_WIDTH-1:0] pick_q;
        input [2:0] pos;
        input signed [SAMPLE_WIDTH-1:0] q0, q1, q2, q3, q4;
        begin
            case (pos)
                3'd0: pick_q = q0;
                3'd1: pick_q = q1;
                3'd2: pick_q = q2;
                3'd3: pick_q = q3;
                default: pick_q = q4;
            endcase
        end
    endfunction

    function [15:0] pick_m;
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

    function signed [47:0] basis_component;
        input signed [SAMPLE_WIDTH-1:0] comp;
        input [15:0] amp;
        input [2:0] power;
        reg [15:0] amp_pow;
        reg signed [16:0] amp_pow_signed;
        reg signed [47:0] product;
        begin
            if (power == 0) begin
                basis_component = comp;
            end else begin
                amp_pow = amp_power(amp, power);
                amp_pow_signed = {1'b0, amp_pow};
                product = comp * amp_pow_signed;
                basis_component = product >>> 15;
            end
        end
    endfunction

    function signed [SAMPLE_WIDTH-1:0] sat_model_error;
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

    function signed [COEF_WIDTH-1:0] sat_coef_add;
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

    function signed [47:0] basis_i_term;
        input [5:0] idx;
        begin
            basis_i_term = basis_component(pick_i(term_x_pos(idx), n_fb_i0, n_fb_i1, n_fb_i2, n_fb_i3, n_fb_i4),
                                           pick_m(term_amp_pos(idx), n_m0, n_m1, n_m2, n_m3, n_m4),
                                           term_power(idx));
        end
    endfunction

    function signed [47:0] basis_q_term;
        input [5:0] idx;
        begin
            basis_q_term = basis_component(pick_q(term_x_pos(idx), n_fb_q0, n_fb_q1, n_fb_q2, n_fb_q3, n_fb_q4),
                                           pick_m(term_amp_pos(idx), n_m0, n_m1, n_m2, n_m3, n_m4),
                                           term_power(idx));
        end
    endfunction

    function signed [ACC_WIDTH-1:0] corr_real_term;
        input [5:0] idx;
        reg signed [47:0] bi;
        reg signed [47:0] bq;
        reg signed [63:0] prod;
        begin
            bi = basis_i_term(idx);
            bq = basis_q_term(idx);
            prod = (model_err_i * bi) + (model_err_q * bq);
            corr_real_term = prod[ACC_WIDTH-1:0];
        end
    endfunction

    function signed [ACC_WIDTH-1:0] corr_imag_term;
        input [5:0] idx;
        reg signed [47:0] bi;
        reg signed [47:0] bq;
        reg signed [63:0] prod;
        begin
            bi = basis_i_term(idx);
            bq = basis_q_term(idx);
            prod = (model_err_q * bi) - (model_err_i * bq);
            corr_imag_term = prod[ACC_WIDTH-1:0];
        end
    endfunction

    function signed [47:0] model_acc_i;
        integer idx;
        reg signed [47:0] bi;
        reg signed [47:0] bq;
        reg signed [65:0] prod_i;
        reg signed [47:0] acc;
        begin
            acc = 48'sd0;
            for (idx = 0; idx < N_GMP_TERMS; idx = idx + 1) begin
                if ((coef_real_cur[idx] != {COEF_WIDTH{1'b0}}) ||
                    (coef_imag_cur[idx] != {COEF_WIDTH{1'b0}})) begin
                    bi = basis_i_term(idx[5:0]);
                    bq = basis_q_term(idx[5:0]);
                    prod_i = (bi * coef_real_cur[idx]) - (bq * coef_imag_cur[idx]);
                    acc = acc + (prod_i >>> 16);
                end
            end
            model_acc_i = acc;
        end
    endfunction

    function signed [47:0] model_acc_q;
        integer idx;
        reg signed [47:0] bi;
        reg signed [47:0] bq;
        reg signed [65:0] prod_q;
        reg signed [47:0] acc;
        begin
            acc = 48'sd0;
            for (idx = 0; idx < N_GMP_TERMS; idx = idx + 1) begin
                if ((coef_real_cur[idx] != {COEF_WIDTH{1'b0}}) ||
                    (coef_imag_cur[idx] != {COEF_WIDTH{1'b0}})) begin
                    bi = basis_i_term(idx[5:0]);
                    bq = basis_q_term(idx[5:0]);
                    prod_q = (bi * coef_imag_cur[idx]) + (bq * coef_real_cur[idx]);
                    acc = acc + (prod_q >>> 16);
                end
            end
            model_acc_q = acc;
        end
    endfunction

    function [ACC_WIDTH-1:0] energy_term;
        input [5:0] idx;
        reg signed [47:0] bi;
        reg signed [47:0] bq;
        reg [63:0] prod;
        begin
            bi = basis_i_term(idx);
            bq = basis_q_term(idx);
            prod = (bi * bi) + (bq * bq);
            energy_term = prod[ACC_WIDTH-1:0];
        end
    endfunction

    function [ACC_WIDTH-1:0] abs_acc;
        input signed [ACC_WIDTH-1:0] value;
        begin
            abs_acc = value[ACC_WIDTH-1] ? -value : value;
        end
    endfunction

    function signed [COEF_WIDTH-1:0] sat_q2_16;
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

    task start_nlms_division;
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
            valid_count <= 3'd0;
            term_idx <= 6'd0;
            epoch_count <= 5'd0;
            have_best <= 1'b0;
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
            fb_i0 <= 0; fb_q0 <= 0; fb_i1 <= 0; fb_q1 <= 0; fb_i2 <= 0; fb_q2 <= 0; fb_i3 <= 0; fb_q3 <= 0; fb_i4 <= 0; fb_q4 <= 0;
            ref_i0 <= 0; ref_q0 <= 0; ref_i1 <= 0; ref_q1 <= 0; ref_i2 <= 0; ref_q2 <= 0; ref_i3 <= 0; ref_q3 <= 0; ref_i4 <= 0; ref_q4 <= 0;
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
                            valid_count <= 3'd0;
                            term_idx <= 6'd0;
                            epoch_count <= 5'd0;
                            have_best <= 1'b0;
                            mac_rd_addr <= {CAPTURE_ADDR_WIDTH{1'b0}};
                            status_error_acc <= 32'd0;
                            epoch_model_error_acc <= {ACC_WIDTH{1'b0}};
                            best_model_error_acc <= {ACC_WIDTH{1'b1}};
                            fb_i0 <= 0; fb_q0 <= 0; fb_i1 <= 0; fb_q1 <= 0; fb_i2 <= 0; fb_q2 <= 0; fb_i3 <= 0; fb_q3 <= 0; fb_i4 <= 0; fb_q4 <= 0;
                            ref_i0 <= 0; ref_q0 <= 0; ref_i1 <= 0; ref_q1 <= 0; ref_i2 <= 0; ref_q2 <= 0; ref_i3 <= 0; ref_q3 <= 0; ref_i4 <= 0; ref_q4 <= 0;
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
                    state <= STATE_ACCUM;
                end

                STATE_ACCUM: begin
                    train_busy <= 1'b1;
                    capture_lock <= 1'b1;
                    status_error_acc <= status_error_acc + abs_err_i + abs_err_q;

                    if (produce_window) begin
                        epoch_model_error_acc <= epoch_model_error_acc + abs_model_err_i + abs_model_err_q;
                        for (k = 0; k < N_GMP_TERMS; k = k + 1) begin
                            acc_num_real[k] <= acc_num_real[k] + corr_real_term(k[5:0]);
                            acc_num_imag[k] <= acc_num_imag[k] + corr_imag_term(k[5:0]);
                            acc_den[k] <= acc_den[k] + energy_term(k[5:0]);
                        end
                    end

                    fb_i0 <= n_fb_i0; fb_q0 <= n_fb_q0; fb_i1 <= n_fb_i1; fb_q1 <= n_fb_q1; fb_i2 <= n_fb_i2; fb_q2 <= n_fb_q2; fb_i3 <= n_fb_i3; fb_q3 <= n_fb_q3; fb_i4 <= n_fb_i4; fb_q4 <= n_fb_q4;
                    ref_i0 <= n_ref_i0; ref_q0 <= n_ref_q0; ref_i1 <= n_ref_i1; ref_q1 <= n_ref_q1; ref_i2 <= n_ref_i2; ref_q2 <= n_ref_q2; ref_i3 <= n_ref_i3; ref_q3 <= n_ref_q3; ref_i4 <= n_ref_i4; ref_q4 <= n_ref_q4;
                    if (valid_count < 3'd5)
                        valid_count <= valid_count + 1'b1;

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
                        state <= STATE_EPOCH_DONE;
                    end else begin
                        term_idx <= term_idx + 1'b1;
                        state <= STATE_DIV_REAL_START;
                    end
                end

                STATE_EPOCH_DONE: begin
                    train_busy <= 1'b1;
                    capture_lock <= 1'b1;

                    if (!have_best || (epoch_model_error_acc < best_model_error_acc)) begin
                        have_best <= 1'b1;
                        best_model_error_acc <= epoch_model_error_acc;
                        for (k = 0; k < N_GMP_TERMS; k = k + 1) begin
                            coef_real_best[k] <= coef_real_cur[k];
                            coef_imag_best[k] <= coef_imag_cur[k];
                        end
                    end

                    if ((epoch_count >= NLMS_MAX_EPOCHS-1) ||
                        (have_best && epoch_count >= NLMS_MIN_EPOCHS &&
                         epoch_model_error_acc > best_model_error_acc)) begin
                        term_idx <= 6'd0;
                        state <= STATE_WRITE_BEST_REAL;
                    end else begin
                        epoch_count <= epoch_count + 1'b1;
                        sample_count <= {TRAIN_COUNT_WIDTH{1'b0}};
                        valid_count <= 3'd0;
                        term_idx <= 6'd0;
                        mac_rd_addr <= {CAPTURE_ADDR_WIDTH{1'b0}};
                        epoch_model_error_acc <= {ACC_WIDTH{1'b0}};
                        for (k = 0; k < N_GMP_TERMS; k = k + 1) begin
                            acc_num_real[k] <= {ACC_WIDTH{1'b0}};
                            acc_num_imag[k] <= {ACC_WIDTH{1'b0}};
                            acc_den[k] <= {ACC_WIDTH{1'b0}};
                        end
                        fb_i0 <= 0; fb_q0 <= 0; fb_i1 <= 0; fb_q1 <= 0; fb_i2 <= 0; fb_q2 <= 0; fb_i3 <= 0; fb_q3 <= 0; fb_i4 <= 0; fb_q4 <= 0;
                        ref_i0 <= 0; ref_q0 <= 0; ref_i1 <= 0; ref_q1 <= 0; ref_i2 <= 0; ref_q2 <= 0; ref_i3 <= 0; ref_q3 <= 0; ref_i4 <= 0; ref_q4 <= 0;
                        state <= STATE_READ;
                    end
                end

                STATE_WRITE_BEST_REAL: begin
                    train_busy <= 1'b1;
                    capture_lock <= 1'b1;
                    coef_we <= 1'b1;
                    coef_addr <= {term_idx, 1'b0};
                    coef_wdata <= coef_real_best[term_idx];
                    state <= STATE_WRITE_BEST_IMAG;
                end

                STATE_WRITE_BEST_IMAG: begin
                    train_busy <= 1'b1;
                    capture_lock <= 1'b1;
                    coef_we <= 1'b1;
                    coef_addr <= {term_idx, 1'b1};
                    coef_wdata <= coef_imag_best[term_idx];
                    if (term_idx == N_GMP_TERMS-1) begin
                        state <= STATE_DONE;
                    end else begin
                        term_idx <= term_idx + 1'b1;
                        state <= STATE_WRITE_BEST_REAL;
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
