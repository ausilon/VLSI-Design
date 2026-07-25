// ============================================================
// gmp_engine.v - Pipelined OpenDPD-compatible GMP inference engine
//
// Full HDL model:
//   - 39 OpenDPD GMP terms for memory_length=3, degree=5
//   - complex coefficients: real/imag signed Q2.16 in adjacent addresses
//   - signed Q1.15 I/Q samples
//   - 2-sample lookahead to support OpenDPD leading terms
//   - one accepted sample per clock after coefficient cache load
//
// Pipeline:
//   S0: form 5-sample lookahead window
//   S1: compute |x| magnitudes
//   S2: accumulate terms  0..9
//   S3: accumulate terms 10..19
//   S4: accumulate terms 20..29
//   S5: accumulate terms 30..38 and register output
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
    localparam STATE_LOAD = 1'b0;
    localparam STATE_RUN  = 1'b1;

    reg state;
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

    reg s0_valid;
    reg signed [SAMPLE_WIDTH-1:0] s0_i0, s0_q0, s0_i1, s0_q1, s0_i2, s0_q2, s0_i3, s0_q3, s0_i4, s0_q4;

    reg s1_valid;
    reg signed [SAMPLE_WIDTH-1:0] s1_i0, s1_q0, s1_i1, s1_q1, s1_i2, s1_q2, s1_i3, s1_q3, s1_i4, s1_q4;
    reg [15:0] s1_m0, s1_m1, s1_m2, s1_m3, s1_m4;

    reg s2_valid;
    reg signed [SAMPLE_WIDTH-1:0] s2_i0, s2_q0, s2_i1, s2_q1, s2_i2, s2_q2, s2_i3, s2_q3, s2_i4, s2_q4;
    reg [15:0] s2_m0, s2_m1, s2_m2, s2_m3, s2_m4;
    reg signed [47:0] s2_acc_i, s2_acc_q;

    reg s3_valid;
    reg signed [SAMPLE_WIDTH-1:0] s3_i0, s3_q0, s3_i1, s3_q1, s3_i2, s3_q2, s3_i3, s3_q3, s3_i4, s3_q4;
    reg [15:0] s3_m0, s3_m1, s3_m2, s3_m3, s3_m4;
    reg signed [47:0] s3_acc_i, s3_acc_q;

    reg s4_valid;
    reg signed [SAMPLE_WIDTH-1:0] s4_i0, s4_q0, s4_i1, s4_q1, s4_i2, s4_q2, s4_i3, s4_q3, s4_i4, s4_q4;
    reg [15:0] s4_m0, s4_m1, s4_m2, s4_m3, s4_m4;
    reg signed [47:0] s4_acc_i, s4_acc_q;

    wire can_accept_output = !out_valid || out_ready;
    wire pipe_ce = can_accept_output;
    wire run_ready = (state == STATE_RUN) && coeff_loaded && pipe_ce;

    assign in_ready = enable ? run_ready : can_accept_output;
    assign busy = enable && ((state != STATE_RUN) || !coeff_loaded || !pipe_ce);

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

    wire accept_sample = in_valid && in_ready;
    wire produce_window = enable && accept_sample && (valid_count >= 3'd2);

    integer k;

    function signed [SAMPLE_WIDTH-1:0] sat16;
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

    function signed [47:0] group_acc_i;
        input integer start_idx;
        input integer stop_idx;
        input signed [SAMPLE_WIDTH-1:0] i0, q0, i1, q1, i2, q2, i3, q3, i4, q4;
        input [15:0] m0, m1, m2, m3, m4;
        integer idx;
        reg signed [47:0] basis_i;
        reg signed [47:0] basis_q;
        reg signed [65:0] prod_i;
        begin
            group_acc_i = 48'sd0;
            for (idx = start_idx; idx < stop_idx; idx = idx + 1) begin
                basis_i = basis_component(pick_i(term_x_pos(idx[5:0]), i0, i1, i2, i3, i4),
                                          pick_m(term_amp_pos(idx[5:0]), m0, m1, m2, m3, m4),
                                          term_power(idx[5:0]));
                basis_q = basis_component(pick_q(term_x_pos(idx[5:0]), q0, q1, q2, q3, q4),
                                          pick_m(term_amp_pos(idx[5:0]), m0, m1, m2, m3, m4),
                                          term_power(idx[5:0]));
                prod_i = (basis_i * coef_real[idx]) - (basis_q * coef_imag[idx]);
                group_acc_i = group_acc_i + (prod_i >>> 16);
            end
        end
    endfunction

    function signed [47:0] group_acc_q;
        input integer start_idx;
        input integer stop_idx;
        input signed [SAMPLE_WIDTH-1:0] i0, q0, i1, q1, i2, q2, i3, q3, i4, q4;
        input [15:0] m0, m1, m2, m3, m4;
        integer idx;
        reg signed [47:0] basis_i;
        reg signed [47:0] basis_q;
        reg signed [65:0] prod_q;
        begin
            group_acc_q = 48'sd0;
            for (idx = start_idx; idx < stop_idx; idx = idx + 1) begin
                basis_i = basis_component(pick_i(term_x_pos(idx[5:0]), i0, i1, i2, i3, i4),
                                          pick_m(term_amp_pos(idx[5:0]), m0, m1, m2, m3, m4),
                                          term_power(idx[5:0]));
                basis_q = basis_component(pick_q(term_x_pos(idx[5:0]), q0, q1, q2, q3, q4),
                                          pick_m(term_amp_pos(idx[5:0]), m0, m1, m2, m3, m4),
                                          term_power(idx[5:0]));
                prod_q = (basis_i * coef_imag[idx]) + (basis_q * coef_real[idx]);
                group_acc_q = group_acc_q + (prod_q >>> 16);
            end
        end
    endfunction

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state <= STATE_LOAD;
            coeff_loaded <= 1'b0;
            load_addr <= {COEF_ADDR_WIDTH{1'b0}};
            coef_addr <= {COEF_ADDR_WIDTH{1'b0}};
            valid_count <= 3'd0;
            x_i0 <= 0; x_q0 <= 0; x_i1 <= 0; x_q1 <= 0; x_i2 <= 0; x_q2 <= 0; x_i3 <= 0; x_q3 <= 0; x_i4 <= 0; x_q4 <= 0;
            s0_valid <= 1'b0; s1_valid <= 1'b0; s2_valid <= 1'b0; s3_valid <= 1'b0; s4_valid <= 1'b0;
            s2_acc_i <= 48'sd0; s2_acc_q <= 48'sd0; s3_acc_i <= 48'sd0; s3_acc_q <= 48'sd0; s4_acc_i <= 48'sd0; s4_acc_q <= 48'sd0;
            i_out <= 0; q_out <= 0; out_valid <= 1'b0;
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
                valid_count <= 3'd0;
                x_i0 <= 0; x_q0 <= 0; x_i1 <= 0; x_q1 <= 0; x_i2 <= 0; x_q2 <= 0; x_i3 <= 0; x_q3 <= 0; x_i4 <= 0; x_q4 <= 0;
                s0_valid <= 1'b0; s1_valid <= 1'b0; s2_valid <= 1'b0; s3_valid <= 1'b0; s4_valid <= 1'b0;
            end else if (state == STATE_LOAD) begin
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

            if (accept_sample && !enable) begin
                i_out <= i_in;
                q_out <= q_in;
                out_valid <= 1'b1;
            end else if (pipe_ce) begin
                if (s4_valid) begin
                    i_out <= sat16(s4_acc_i + group_acc_i(30, 39, s4_i0, s4_q0, s4_i1, s4_q1, s4_i2, s4_q2, s4_i3, s4_q3, s4_i4, s4_q4, s4_m0, s4_m1, s4_m2, s4_m3, s4_m4));
                    q_out <= sat16(s4_acc_q + group_acc_q(30, 39, s4_i0, s4_q0, s4_i1, s4_q1, s4_i2, s4_q2, s4_i3, s4_q3, s4_i4, s4_q4, s4_m0, s4_m1, s4_m2, s4_m3, s4_m4));
                end
                out_valid <= s4_valid;

                s4_valid <= s3_valid;
                s4_i0 <= s3_i0; s4_q0 <= s3_q0; s4_i1 <= s3_i1; s4_q1 <= s3_q1; s4_i2 <= s3_i2; s4_q2 <= s3_q2; s4_i3 <= s3_i3; s4_q3 <= s3_q3; s4_i4 <= s3_i4; s4_q4 <= s3_q4;
                s4_m0 <= s3_m0; s4_m1 <= s3_m1; s4_m2 <= s3_m2; s4_m3 <= s3_m3; s4_m4 <= s3_m4;
                s4_acc_i <= s3_acc_i + group_acc_i(20, 30, s3_i0, s3_q0, s3_i1, s3_q1, s3_i2, s3_q2, s3_i3, s3_q3, s3_i4, s3_q4, s3_m0, s3_m1, s3_m2, s3_m3, s3_m4);
                s4_acc_q <= s3_acc_q + group_acc_q(20, 30, s3_i0, s3_q0, s3_i1, s3_q1, s3_i2, s3_q2, s3_i3, s3_q3, s3_i4, s3_q4, s3_m0, s3_m1, s3_m2, s3_m3, s3_m4);

                s3_valid <= s2_valid;
                s3_i0 <= s2_i0; s3_q0 <= s2_q0; s3_i1 <= s2_i1; s3_q1 <= s2_q1; s3_i2 <= s2_i2; s3_q2 <= s2_q2; s3_i3 <= s2_i3; s3_q3 <= s2_q3; s3_i4 <= s2_i4; s3_q4 <= s2_q4;
                s3_m0 <= s2_m0; s3_m1 <= s2_m1; s3_m2 <= s2_m2; s3_m3 <= s2_m3; s3_m4 <= s2_m4;
                s3_acc_i <= s2_acc_i + group_acc_i(10, 20, s2_i0, s2_q0, s2_i1, s2_q1, s2_i2, s2_q2, s2_i3, s2_q3, s2_i4, s2_q4, s2_m0, s2_m1, s2_m2, s2_m3, s2_m4);
                s3_acc_q <= s2_acc_q + group_acc_q(10, 20, s2_i0, s2_q0, s2_i1, s2_q1, s2_i2, s2_q2, s2_i3, s2_q3, s2_i4, s2_q4, s2_m0, s2_m1, s2_m2, s2_m3, s2_m4);

                s2_valid <= s1_valid;
                s2_i0 <= s1_i0; s2_q0 <= s1_q0; s2_i1 <= s1_i1; s2_q1 <= s1_q1; s2_i2 <= s1_i2; s2_q2 <= s1_q2; s2_i3 <= s1_i3; s2_q3 <= s1_q3; s2_i4 <= s1_i4; s2_q4 <= s1_q4;
                s2_m0 <= s1_m0; s2_m1 <= s1_m1; s2_m2 <= s1_m2; s2_m3 <= s1_m3; s2_m4 <= s1_m4;
                s2_acc_i <= group_acc_i(0, 10, s1_i0, s1_q0, s1_i1, s1_q1, s1_i2, s1_q2, s1_i3, s1_q3, s1_i4, s1_q4, s1_m0, s1_m1, s1_m2, s1_m3, s1_m4);
                s2_acc_q <= group_acc_q(0, 10, s1_i0, s1_q0, s1_i1, s1_q1, s1_i2, s1_q2, s1_i3, s1_q3, s1_i4, s1_q4, s1_m0, s1_m1, s1_m2, s1_m3, s1_m4);

                s1_valid <= s0_valid;
                s1_i0 <= s0_i0; s1_q0 <= s0_q0; s1_i1 <= s0_i1; s1_q1 <= s0_q1; s1_i2 <= s0_i2; s1_q2 <= s0_q2; s1_i3 <= s0_i3; s1_q3 <= s0_q3; s1_i4 <= s0_i4; s1_q4 <= s0_q4;
                s1_m0 <= mag_q15(s0_i0, s0_q0); s1_m1 <= mag_q15(s0_i1, s0_q1); s1_m2 <= mag_q15(s0_i2, s0_q2); s1_m3 <= mag_q15(s0_i3, s0_q3); s1_m4 <= mag_q15(s0_i4, s0_q4);

                s0_valid <= produce_window;
                if (accept_sample && enable) begin
                    s0_i0 <= n_i0; s0_q0 <= n_q0; s0_i1 <= n_i1; s0_q1 <= n_q1; s0_i2 <= n_i2; s0_q2 <= n_q2; s0_i3 <= n_i3; s0_q3 <= n_q3; s0_i4 <= n_i4; s0_q4 <= n_q4;
                    x_i0 <= n_i0; x_q0 <= n_q0; x_i1 <= n_i1; x_q1 <= n_q1; x_i2 <= n_i2; x_q2 <= n_q2; x_i3 <= n_i3; x_q3 <= n_q3; x_i4 <= n_i4; x_q4 <= n_q4;
                    if (valid_count < 3'd5)
                        valid_count <= valid_count + 1'b1;
                end
            end
        end
    end
endmodule
