// ============================================================
// gmp_mac_lane.v - fixed-latency single-term complex GMP lane
//
// Contract:
//   - one GMP term per lane per issue cycle
//   - signed Q1.15 samples
//   - signed Q2.16 complex coefficients
//   - output term is in Q1.15 accumulator scale
//
// Pipeline contract:
//   - fixed internal lane latency from accepted term to registered output
//   - valid_o, slot_o, phase_o and term_i_o/term_q_o remain aligned
//   - term index 39 is a valid zero slot used to complete phase 3
//   - invalid issue cycles drive zero terms and valid_o=0
//
// The arithmetic mirrors the bit-exact rtl_v2 model, but the mux/base/product/
// complex-combine path is split into registered stages for SKY130 timing.
// ============================================================
module gmp_mac_lane #(
    parameter SAMPLE_WIDTH = 16,
    parameter COEF_WIDTH = 18
)(
    input  wire clk,
    input  wire resetn,
    input  wire valid_i,
    input  wire slot_i,
    input  wire [1:0] phase_i,
    input  wire [5:0] term_idx_i,

    input  wire signed [SAMPLE_WIDTH-1:0] i0_i,
    input  wire signed [SAMPLE_WIDTH-1:0] q0_i,
    input  wire signed [SAMPLE_WIDTH-1:0] i1_i,
    input  wire signed [SAMPLE_WIDTH-1:0] q1_i,
    input  wire signed [SAMPLE_WIDTH-1:0] i2_i,
    input  wire signed [SAMPLE_WIDTH-1:0] q2_i,
    input  wire signed [SAMPLE_WIDTH-1:0] i3_i,
    input  wire signed [SAMPLE_WIDTH-1:0] q3_i,
    input  wire signed [SAMPLE_WIDTH-1:0] i4_i,
    input  wire signed [SAMPLE_WIDTH-1:0] q4_i,

    input  wire [15:0] m0_i,
    input  wire [15:0] m1_i,
    input  wire [15:0] m2_i,
    input  wire [15:0] m3_i,
    input  wire [15:0] m4_i,
    input  wire [15:0] p20_i,
    input  wire [15:0] p21_i,
    input  wire [15:0] p22_i,
    input  wire [15:0] p23_i,
    input  wire [15:0] p24_i,
    input  wire [15:0] p30_i,
    input  wire [15:0] p31_i,
    input  wire [15:0] p32_i,
    input  wire [15:0] p33_i,
    input  wire [15:0] p34_i,
    input  wire [15:0] p40_i,
    input  wire [15:0] p41_i,
    input  wire [15:0] p42_i,
    input  wire [15:0] p43_i,
    input  wire [15:0] p44_i,

    input  wire signed [COEF_WIDTH-1:0] coef_real_i,
    input  wire signed [COEF_WIDTH-1:0] coef_imag_i,

    output reg valid_o,
    output reg slot_o,
    output reg [1:0] phase_o,
    output reg signed [47:0] term_i_o,
    output reg signed [47:0] term_q_o
);
    localparam N_TERMS = 39;
    localparam LANE_LATENCY = 3;

    wire active_w = valid_i && (term_idx_i < N_TERMS);
    wire [2:0] term_x_pos_w = term_x_pos(term_idx_i);
    wire [2:0] term_amp_pos_w = term_amp_pos(term_idx_i);
    wire [2:0] term_power_w = term_power(term_idx_i);

    reg s0_valid;
    reg s0_slot;
    reg [1:0] s0_phase;
    reg signed [SAMPLE_WIDTH-1:0] s0_i;
    reg signed [SAMPLE_WIDTH-1:0] s0_q;
    reg [15:0] s0_amp_pow;
    reg [2:0] s0_power;
    reg signed [COEF_WIDTH-1:0] s0_coef_real;
    reg signed [COEF_WIDTH-1:0] s0_coef_imag;

    wire signed [47:0] s0_basis_i_w = basis_component(s0_i, s0_amp_pow, s0_power);
    wire signed [47:0] s0_basis_q_w = basis_component(s0_q, s0_amp_pow, s0_power);

    reg s1_valid;
    reg s1_slot;
    reg [1:0] s1_phase;
    reg signed [47:0] s1_basis_i;
    reg signed [47:0] s1_basis_q;
    reg signed [COEF_WIDTH-1:0] s1_coef_real;
    reg signed [COEF_WIDTH-1:0] s1_coef_imag;

    wire signed [65:0] s1_prod_ir_w = s1_basis_i * s1_coef_real;
    wire signed [65:0] s1_prod_qi_w = s1_basis_q * s1_coef_imag;
    wire signed [65:0] s1_prod_ii_w = s1_basis_i * s1_coef_imag;
    wire signed [65:0] s1_prod_qr_w = s1_basis_q * s1_coef_real;

    reg s2_valid;
    reg s2_slot;
    reg [1:0] s2_phase;
    reg signed [65:0] s2_prod_ir;
    reg signed [65:0] s2_prod_qi;
    reg signed [65:0] s2_prod_ii;
    reg signed [65:0] s2_prod_qr;

    wire signed [65:0] s2_sum_i_w = s2_prod_ir - s2_prod_qi;
    wire signed [65:0] s2_sum_q_w = s2_prod_ii + s2_prod_qr;

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
                3'd0: pick_i = i0_i;
                3'd1: pick_i = i1_i;
                3'd2: pick_i = i2_i;
                3'd3: pick_i = i3_i;
                default: pick_i = i4_i;
            endcase
        end
    endfunction

    function automatic signed [SAMPLE_WIDTH-1:0] pick_q;
        input [2:0] pos;
        begin
            case (pos)
                3'd0: pick_q = q0_i;
                3'd1: pick_q = q1_i;
                3'd2: pick_q = q2_i;
                3'd3: pick_q = q3_i;
                default: pick_q = q4_i;
            endcase
        end
    endfunction

    function automatic [15:0] pick_m;
        input [2:0] pos;
        begin
            case (pos)
                3'd0: pick_m = m0_i;
                3'd1: pick_m = m1_i;
                3'd2: pick_m = m2_i;
                3'd3: pick_m = m3_i;
                default: pick_m = m4_i;
            endcase
        end
    endfunction

    function automatic [15:0] pick_p2;
        input [2:0] pos;
        begin
            case (pos)
                3'd0: pick_p2 = p20_i;
                3'd1: pick_p2 = p21_i;
                3'd2: pick_p2 = p22_i;
                3'd3: pick_p2 = p23_i;
                default: pick_p2 = p24_i;
            endcase
        end
    endfunction

    function automatic [15:0] pick_p3;
        input [2:0] pos;
        begin
            case (pos)
                3'd0: pick_p3 = p30_i;
                3'd1: pick_p3 = p31_i;
                3'd2: pick_p3 = p32_i;
                3'd3: pick_p3 = p33_i;
                default: pick_p3 = p34_i;
            endcase
        end
    endfunction

    function automatic [15:0] pick_p4;
        input [2:0] pos;
        begin
            case (pos)
                3'd0: pick_p4 = p40_i;
                3'd1: pick_p4 = p41_i;
                3'd2: pick_p4 = p42_i;
                3'd3: pick_p4 = p43_i;
                default: pick_p4 = p44_i;
            endcase
        end
    endfunction

    function automatic [15:0] pick_amp_power;
        input [2:0] pos;
        input [2:0] power;
        begin
            case (power)
                3'd0: pick_amp_power = 16'h7fff;
                3'd1: pick_amp_power = pick_m(pos);
                3'd2: pick_amp_power = pick_p2(pos);
                3'd3: pick_amp_power = pick_p3(pos);
                default: pick_amp_power = pick_p4(pos);
            endcase
        end
    endfunction

    function automatic signed [47:0] basis_component;
        input signed [SAMPLE_WIDTH-1:0] comp;
        input [15:0] amp_pow;
        input [2:0] power;
        reg signed [16:0] amp_pow_signed;
        reg signed [47:0] product;
        begin
            if (power == 3'd0) begin
                basis_component = comp;
            end else begin
                amp_pow_signed = {1'b0, amp_pow};
                product = comp * amp_pow_signed;
                basis_component = product >>> 15;
            end
        end
    endfunction

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            s0_valid <= 1'b0;
            s0_slot <= 1'b0;
            s0_phase <= 2'd0;
            s0_i <= {SAMPLE_WIDTH{1'b0}};
            s0_q <= {SAMPLE_WIDTH{1'b0}};
            s0_amp_pow <= 16'd0;
            s0_power <= 3'd0;
            s0_coef_real <= {COEF_WIDTH{1'b0}};
            s0_coef_imag <= {COEF_WIDTH{1'b0}};
            s1_valid <= 1'b0;
            s1_slot <= 1'b0;
            s1_phase <= 2'd0;
            s1_basis_i <= 48'sd0;
            s1_basis_q <= 48'sd0;
            s1_coef_real <= {COEF_WIDTH{1'b0}};
            s1_coef_imag <= {COEF_WIDTH{1'b0}};
            s2_valid <= 1'b0;
            s2_slot <= 1'b0;
            s2_phase <= 2'd0;
            s2_prod_ir <= 66'sd0;
            s2_prod_qi <= 66'sd0;
            s2_prod_ii <= 66'sd0;
            s2_prod_qr <= 66'sd0;
            valid_o <= 1'b0;
            slot_o <= 1'b0;
            phase_o <= 2'd0;
            term_i_o <= 48'sd0;
            term_q_o <= 48'sd0;
        end else begin
            s0_valid <= valid_i;
            s0_slot <= slot_i;
            s0_phase <= phase_i;
            if (active_w) begin
                s0_i <= pick_i(term_x_pos_w);
                s0_q <= pick_q(term_x_pos_w);
                s0_amp_pow <= pick_amp_power(term_amp_pos_w, term_power_w);
                s0_power <= term_power_w;
                s0_coef_real <= coef_real_i;
                s0_coef_imag <= coef_imag_i;
            end else begin
                s0_i <= {SAMPLE_WIDTH{1'b0}};
                s0_q <= {SAMPLE_WIDTH{1'b0}};
                s0_amp_pow <= 16'd0;
                s0_power <= 3'd0;
                s0_coef_real <= {COEF_WIDTH{1'b0}};
                s0_coef_imag <= {COEF_WIDTH{1'b0}};
            end

            s1_valid <= s0_valid;
            s1_slot <= s0_slot;
            s1_phase <= s0_phase;
            s1_basis_i <= s0_valid ? s0_basis_i_w : 48'sd0;
            s1_basis_q <= s0_valid ? s0_basis_q_w : 48'sd0;
            s1_coef_real <= s0_valid ? s0_coef_real : {COEF_WIDTH{1'b0}};
            s1_coef_imag <= s0_valid ? s0_coef_imag : {COEF_WIDTH{1'b0}};

            s2_valid <= s1_valid;
            s2_slot <= s1_slot;
            s2_phase <= s1_phase;
            s2_prod_ir <= s1_valid ? s1_prod_ir_w : 66'sd0;
            s2_prod_qi <= s1_valid ? s1_prod_qi_w : 66'sd0;
            s2_prod_ii <= s1_valid ? s1_prod_ii_w : 66'sd0;
            s2_prod_qr <= s1_valid ? s1_prod_qr_w : 66'sd0;

            valid_o <= s2_valid;
            slot_o <= s2_slot;
            phase_o <= s2_phase;
            term_i_o <= s2_valid ? (s2_sum_i_w >>> 16) : 48'sd0;
            term_q_o <= s2_valid ? (s2_sum_q_w >>> 16) : 48'sd0;
        end
    end
endmodule
