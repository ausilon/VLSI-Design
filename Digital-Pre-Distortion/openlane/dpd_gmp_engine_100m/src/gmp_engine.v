// ============================================================
// gmp_engine.v - OpenLane area-oriented serial GMP engine
//
// OpenLane-only snapshot variant:
//   - same external contract as rtl_v2 gmp_engine
//   - same 39 OpenDPD GMP terms and complex Q2.16 coefficients
//   - same signed Q1.15 I/Q samples and 2-sample lookahead
//   - serializes the 39-term accumulation into 4 internal phases
//   - computes only one new |x| magnitude per accepted sample
//
// Throughput target:
//   At 100 MHz, one accepted DPD sample every 4 cycles gives 25 Msps.
//   This preserves margin above the 24 Msps baseband validation target while
//   avoiding the large fully-parallel 39-term datapath.
//
// Coefficient bank map:
//   addr 2*k+0 = Re{coef[k]}, signed Q2.16 int18
//   addr 2*k+1 = Im{coef[k]}, signed Q2.16 int18
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
    localparam N_COEF_WORDS = 2 * N_TERMS;

    localparam STATE_LOAD = 3'd0;
    localparam STATE_RUN  = 3'd1;
    localparam STATE_G1   = 3'd2;
    localparam STATE_G2   = 3'd3;
    localparam STATE_G3   = 3'd4;

    reg [2:0] state;
    reg coeff_loaded;
    reg [COEF_ADDR_WIDTH-1:0] load_addr;
    reg [2:0] valid_count;

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
    reg signed [47:0] acc_i, acc_q;

    wire can_accept_output = !out_valid || out_ready;
    wire run_ready = (state == STATE_RUN) && coeff_loaded && can_accept_output;

    assign in_ready = enable ? run_ready : can_accept_output;
    assign busy = enable && ((state != STATE_RUN) || !coeff_loaded || !can_accept_output);

    wire signed [SAMPLE_WIDTH-1:0] n_i0 = x_i1;
    wire signed [SAMPLE_WIDTH-1:0] n_q0 = x_q1;
    wire signed [SAMPLE_WIDTH-1:0] n_i1 = x_i2;
    wire signed [SAMPLE_WIDTH-1:0] n_q1 = x_q2;
    wire signed [SAMPLE_WIDTH-1:0] n_i2 = x_i3;
    wire signed [SAMPLE_WIDTH-1:0] n_q2 = x_q3;
    wire signed [SAMPLE_WIDTH-1:0] n_i3 = x_i4;
    wire signed [SAMPLE_WIDTH-1:0] n_q3 = x_q4;
    wire signed [SAMPLE_WIDTH-1:0] n_i4 = i_in;
    wire signed [SAMPLE_WIDTH-1:0] n_q4 = q_in;

    wire [15:0] n_m0 = x_m1;
    wire [15:0] n_m1 = x_m2;
    wire [15:0] n_m2 = x_m3;
    wire [15:0] n_m3 = x_m4;
    wire [15:0] n_m4 = mag_q15(i_in, q_in);

    wire [15:0] n_p20 = x_p21;
    wire [15:0] n_p21 = x_p22;
    wire [15:0] n_p22 = x_p23;
    wire [15:0] n_p23 = x_p24;
    wire [15:0] n_p24 = q15_umult(n_m4, n_m4);
    wire [15:0] n_p30 = x_p31;
    wire [15:0] n_p31 = x_p32;
    wire [15:0] n_p32 = x_p33;
    wire [15:0] n_p33 = x_p34;
    wire [15:0] n_p34 = q15_umult(n_p24, n_m4);
    wire [15:0] n_p40 = x_p41;
    wire [15:0] n_p41 = x_p42;
    wire [15:0] n_p42 = x_p43;
    wire [15:0] n_p43 = x_p44;
    wire [15:0] n_p44 = q15_umult(n_p34, n_m4);

    wire accept_sample = in_valid && in_ready;
    wire produce_window = enable && accept_sample && (valid_count >= 3'd2);
    wire phase_uses_new_window = (state == STATE_RUN) && produce_window;
    wire [1:0] phase_sel =
        (state == STATE_G1) ? 2'd1 :
        (state == STATE_G2) ? 2'd2 :
        (state == STATE_G3) ? 2'd3 : 2'd0;

    wire signed [SAMPLE_WIDTH-1:0] phase_i0 = phase_uses_new_window ? n_i0 : w_i0;
    wire signed [SAMPLE_WIDTH-1:0] phase_q0 = phase_uses_new_window ? n_q0 : w_q0;
    wire signed [SAMPLE_WIDTH-1:0] phase_i1 = phase_uses_new_window ? n_i1 : w_i1;
    wire signed [SAMPLE_WIDTH-1:0] phase_q1 = phase_uses_new_window ? n_q1 : w_q1;
    wire signed [SAMPLE_WIDTH-1:0] phase_i2 = phase_uses_new_window ? n_i2 : w_i2;
    wire signed [SAMPLE_WIDTH-1:0] phase_q2 = phase_uses_new_window ? n_q2 : w_q2;
    wire signed [SAMPLE_WIDTH-1:0] phase_i3 = phase_uses_new_window ? n_i3 : w_i3;
    wire signed [SAMPLE_WIDTH-1:0] phase_q3 = phase_uses_new_window ? n_q3 : w_q3;
    wire signed [SAMPLE_WIDTH-1:0] phase_i4 = phase_uses_new_window ? n_i4 : w_i4;
    wire signed [SAMPLE_WIDTH-1:0] phase_q4 = phase_uses_new_window ? n_q4 : w_q4;

    wire [15:0] phase_m0 = phase_uses_new_window ? n_m0 : w_m0;
    wire [15:0] phase_m1 = phase_uses_new_window ? n_m1 : w_m1;
    wire [15:0] phase_m2 = phase_uses_new_window ? n_m2 : w_m2;
    wire [15:0] phase_m3 = phase_uses_new_window ? n_m3 : w_m3;
    wire [15:0] phase_m4 = phase_uses_new_window ? n_m4 : w_m4;
    wire [15:0] phase_p20 = phase_uses_new_window ? n_p20 : w_p20;
    wire [15:0] phase_p21 = phase_uses_new_window ? n_p21 : w_p21;
    wire [15:0] phase_p22 = phase_uses_new_window ? n_p22 : w_p22;
    wire [15:0] phase_p23 = phase_uses_new_window ? n_p23 : w_p23;
    wire [15:0] phase_p24 = phase_uses_new_window ? n_p24 : w_p24;
    wire [15:0] phase_p30 = phase_uses_new_window ? n_p30 : w_p30;
    wire [15:0] phase_p31 = phase_uses_new_window ? n_p31 : w_p31;
    wire [15:0] phase_p32 = phase_uses_new_window ? n_p32 : w_p32;
    wire [15:0] phase_p33 = phase_uses_new_window ? n_p33 : w_p33;
    wire [15:0] phase_p34 = phase_uses_new_window ? n_p34 : w_p34;
    wire [15:0] phase_p40 = phase_uses_new_window ? n_p40 : w_p40;
    wire [15:0] phase_p41 = phase_uses_new_window ? n_p41 : w_p41;
    wire [15:0] phase_p42 = phase_uses_new_window ? n_p42 : w_p42;
    wire [15:0] phase_p43 = phase_uses_new_window ? n_p43 : w_p43;
    wire [15:0] phase_p44 = phase_uses_new_window ? n_p44 : w_p44;

    wire signed [47:0] phase_acc_i_w;
    wire signed [47:0] phase_acc_q_w;

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

    function automatic signed [SAMPLE_WIDTH-1:0] pick_q;
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

    function automatic signed [47:0] basis_component;
        input signed [SAMPLE_WIDTH-1:0] comp;
        input [15:0] amp;
        input [15:0] amp2;
        input [15:0] amp3;
        input [15:0] amp4;
        input [2:0] power;
        reg [15:0] amp_pow;
        reg signed [16:0] amp_pow_signed;
        reg signed [47:0] product;
        begin
            case (power)
                3'd0: amp_pow = 16'h7fff;
                3'd1: amp_pow = amp;
                3'd2: amp_pow = amp2;
                3'd3: amp_pow = amp3;
                default: amp_pow = amp4;
            endcase
            if (power == 0) begin
                basis_component = comp;
            end else begin
                amp_pow_signed = {1'b0, amp_pow};
                product = comp * amp_pow_signed;
                basis_component = product >>> 15;
            end
        end
    endfunction

    function automatic signed [47:0] phase_acc_i;
        input [1:0] phase;
        input signed [SAMPLE_WIDTH-1:0] i0, q0, i1, q1, i2, q2, i3, q3, i4, q4;
        input [15:0] m0, m1, m2, m3, m4;
        input [15:0] p20, p21, p22, p23, p24;
        input [15:0] p30, p31, p32, p33, p34;
        input [15:0] p40, p41, p42, p43, p44;
        integer lane;
        integer idx;
        reg [2:0] amp_pos;
        reg [2:0] x_pos;
        reg [2:0] power;
        reg signed [47:0] basis_i;
        reg signed [47:0] basis_q;
        reg signed [65:0] prod_i;
        begin
            phase_acc_i = 48'sd0;
            for (lane = 0; lane < 10; lane = lane + 1) begin
                idx = (phase * 10) + lane;
                if (idx < N_TERMS) begin
                    x_pos = term_x_pos(idx[5:0]);
                    amp_pos = term_amp_pos(idx[5:0]);
                    power = term_power(idx[5:0]);
                    basis_i = basis_component(pick_i(x_pos, i0, i1, i2, i3, i4),
                                              pick_m(amp_pos, m0, m1, m2, m3, m4),
                                              pick_m(amp_pos, p20, p21, p22, p23, p24),
                                              pick_m(amp_pos, p30, p31, p32, p33, p34),
                                              pick_m(amp_pos, p40, p41, p42, p43, p44),
                                              power);
                    basis_q = basis_component(pick_q(x_pos, q0, q1, q2, q3, q4),
                                              pick_m(amp_pos, m0, m1, m2, m3, m4),
                                              pick_m(amp_pos, p20, p21, p22, p23, p24),
                                              pick_m(amp_pos, p30, p31, p32, p33, p34),
                                              pick_m(amp_pos, p40, p41, p42, p43, p44),
                                              power);
                    prod_i = (basis_i * coef_real[idx]) - (basis_q * coef_imag[idx]);
                    phase_acc_i = phase_acc_i + (prod_i >>> 16);
                end
            end
        end
    endfunction

    function automatic signed [47:0] phase_acc_q;
        input [1:0] phase;
        input signed [SAMPLE_WIDTH-1:0] i0, q0, i1, q1, i2, q2, i3, q3, i4, q4;
        input [15:0] m0, m1, m2, m3, m4;
        input [15:0] p20, p21, p22, p23, p24;
        input [15:0] p30, p31, p32, p33, p34;
        input [15:0] p40, p41, p42, p43, p44;
        integer lane;
        integer idx;
        reg [2:0] amp_pos;
        reg [2:0] x_pos;
        reg [2:0] power;
        reg signed [47:0] basis_i;
        reg signed [47:0] basis_q;
        reg signed [65:0] prod_q;
        begin
            phase_acc_q = 48'sd0;
            for (lane = 0; lane < 10; lane = lane + 1) begin
                idx = (phase * 10) + lane;
                if (idx < N_TERMS) begin
                    x_pos = term_x_pos(idx[5:0]);
                    amp_pos = term_amp_pos(idx[5:0]);
                    power = term_power(idx[5:0]);
                    basis_i = basis_component(pick_i(x_pos, i0, i1, i2, i3, i4),
                                              pick_m(amp_pos, m0, m1, m2, m3, m4),
                                              pick_m(amp_pos, p20, p21, p22, p23, p24),
                                              pick_m(amp_pos, p30, p31, p32, p33, p34),
                                              pick_m(amp_pos, p40, p41, p42, p43, p44),
                                              power);
                    basis_q = basis_component(pick_q(x_pos, q0, q1, q2, q3, q4),
                                              pick_m(amp_pos, m0, m1, m2, m3, m4),
                                              pick_m(amp_pos, p20, p21, p22, p23, p24),
                                              pick_m(amp_pos, p30, p31, p32, p33, p34),
                                              pick_m(amp_pos, p40, p41, p42, p43, p44),
                                              power);
                    prod_q = (basis_i * coef_imag[idx]) + (basis_q * coef_real[idx]);
                    phase_acc_q = phase_acc_q + (prod_q >>> 16);
                end
            end
        end
    endfunction

    assign phase_acc_i_w = phase_acc_i(phase_sel,
                                       phase_i0, phase_q0, phase_i1, phase_q1, phase_i2, phase_q2, phase_i3, phase_q3, phase_i4, phase_q4,
                                       phase_m0, phase_m1, phase_m2, phase_m3, phase_m4,
                                       phase_p20, phase_p21, phase_p22, phase_p23, phase_p24,
                                       phase_p30, phase_p31, phase_p32, phase_p33, phase_p34,
                                       phase_p40, phase_p41, phase_p42, phase_p43, phase_p44);

    assign phase_acc_q_w = phase_acc_q(phase_sel,
                                       phase_i0, phase_q0, phase_i1, phase_q1, phase_i2, phase_q2, phase_i3, phase_q3, phase_i4, phase_q4,
                                       phase_m0, phase_m1, phase_m2, phase_m3, phase_m4,
                                       phase_p20, phase_p21, phase_p22, phase_p23, phase_p24,
                                       phase_p30, phase_p31, phase_p32, phase_p33, phase_p34,
                                       phase_p40, phase_p41, phase_p42, phase_p43, phase_p44);

    task automatic clear_windows;
        begin
            valid_count <= 3'd0;
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
            acc_i <= 48'sd0;
            acc_q <= 48'sd0;
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
            for (k = 0; k < N_TERMS; k = k + 1) begin
                coef_real[k] <= 0;
                coef_imag[k] <= 0;
            end
        end else begin
            if (out_valid && out_ready)
                out_valid <= 1'b0;

            if (reload_coeffs) begin
                state <= STATE_LOAD;
                coeff_loaded <= 1'b0;
                load_addr <= {COEF_ADDR_WIDTH{1'b0}};
                coef_addr <= {COEF_ADDR_WIDTH{1'b0}};
                clear_windows();
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
                            load_addr <= {COEF_ADDR_WIDTH{1'b0}};
                            coef_addr <= {COEF_ADDR_WIDTH{1'b0}};
                        end else begin
                            load_addr <= load_addr + 1'b1;
                            coef_addr <= load_addr + 1'b1;
                        end
                    end

                    STATE_RUN: begin
                        if (accept_sample && !enable) begin
                            i_out <= i_in;
                            q_out <= q_in;
                            out_valid <= 1'b1;
                        end else if (accept_sample) begin
                            x_i0 <= n_i0; x_q0 <= n_q0; x_m0 <= n_m0;
                            x_i1 <= n_i1; x_q1 <= n_q1; x_m1 <= n_m1;
                            x_i2 <= n_i2; x_q2 <= n_q2; x_m2 <= n_m2;
                            x_i3 <= n_i3; x_q3 <= n_q3; x_m3 <= n_m3;
                            x_i4 <= n_i4; x_q4 <= n_q4; x_m4 <= n_m4;
                            x_p20 <= n_p20; x_p21 <= n_p21; x_p22 <= n_p22; x_p23 <= n_p23; x_p24 <= n_p24;
                            x_p30 <= n_p30; x_p31 <= n_p31; x_p32 <= n_p32; x_p33 <= n_p33; x_p34 <= n_p34;
                            x_p40 <= n_p40; x_p41 <= n_p41; x_p42 <= n_p42; x_p43 <= n_p43; x_p44 <= n_p44;
                            if (valid_count < 3'd5)
                                valid_count <= valid_count + 1'b1;

                            if (produce_window) begin
                                w_i0 <= n_i0; w_q0 <= n_q0; w_m0 <= n_m0;
                                w_i1 <= n_i1; w_q1 <= n_q1; w_m1 <= n_m1;
                                w_i2 <= n_i2; w_q2 <= n_q2; w_m2 <= n_m2;
                                w_i3 <= n_i3; w_q3 <= n_q3; w_m3 <= n_m3;
                                w_i4 <= n_i4; w_q4 <= n_q4; w_m4 <= n_m4;
                                w_p20 <= n_p20; w_p21 <= n_p21; w_p22 <= n_p22; w_p23 <= n_p23; w_p24 <= n_p24;
                                w_p30 <= n_p30; w_p31 <= n_p31; w_p32 <= n_p32; w_p33 <= n_p33; w_p34 <= n_p34;
                                w_p40 <= n_p40; w_p41 <= n_p41; w_p42 <= n_p42; w_p43 <= n_p43; w_p44 <= n_p44;
                                acc_i <= phase_acc_i_w;
                                acc_q <= phase_acc_q_w;
                                state <= STATE_G1;
                            end
                        end
                    end

                    STATE_G1: begin
                        acc_i <= acc_i + phase_acc_i_w;
                        acc_q <= acc_q + phase_acc_q_w;
                        state <= STATE_G2;
                    end

                    STATE_G2: begin
                        acc_i <= acc_i + phase_acc_i_w;
                        acc_q <= acc_q + phase_acc_q_w;
                        state <= STATE_G3;
                    end

                    STATE_G3: begin
                        i_out <= sat16(acc_i + phase_acc_i_w);
                        q_out <= sat16(acc_q + phase_acc_q_w);
                        out_valid <= 1'b1;
                        state <= STATE_RUN;
                    end

                    default: begin
                        state <= STATE_LOAD;
                    end
                endcase
            end
        end
    end
endmodule
