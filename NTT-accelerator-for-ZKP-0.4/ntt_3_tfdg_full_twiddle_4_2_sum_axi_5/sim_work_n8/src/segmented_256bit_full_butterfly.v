`timescale 1ns/1ps

// ============================================================================
// �ļ���: segmented_256bit_full_butterfly.v
// ����: 256λNTT�������㵥Ԫ���ֶ�ʵ�֣�
//
// ��ʽ: y0 = (x0 + x1*w) mod N,  y1 = (x0 - x1*w) mod N
//
// �����ص�:
//   1. ���÷ֶγ˷�16x16λʵ�֣���4��
//   2. Montgomery�˷���Ӽ�����ˮ�߲���
//   3. �ӳ�Լ3���������һ������
//   4. ������: 1����� / (Montgomery�ӳ�+2) ����
// ============================================================================
module segmented_256bit_full_butterfly #(
    parameter TOTAL_WIDTH = 256,
    parameter SEG_WIDTH = 64,
    parameter SEG_COUNT = TOTAL_WIDTH / SEG_WIDTH
)(
    input wire clk,
    input wire rst_n,

    input wire start,
    output reg done,
    output reg busy,

    input wire [TOTAL_WIDTH-1:0] x0,
    input wire [TOTAL_WIDTH-1:0] x1,
    input wire [TOTAL_WIDTH-1:0] w,
    input wire [TOTAL_WIDTH-1:0] N_prime,
    input wire [TOTAL_WIDTH-1:0] modulus,

    output reg [TOTAL_WIDTH-1:0] result_add,
    output reg [TOTAL_WIDTH-1:0] result_sub,
    output reg result_valid
);

// ============================================================================
// �ֶ��ź�
// ============================================================================
wire [SEG_WIDTH-1:0] x0_seg [0:SEG_COUNT-1];
wire [SEG_WIDTH-1:0] x1_seg [0:SEG_COUNT-1];
wire [SEG_WIDTH-1:0] w_seg  [0:SEG_COUNT-1];

genvar gi, gj;
generate
    for (gi = 0; gi < SEG_COUNT; gi = gi + 1) begin : gen_segments
        assign x0_seg[gi] = x0[gi*SEG_WIDTH +: SEG_WIDTH];
        assign x1_seg[gi] = x1[gi*SEG_WIDTH +: SEG_WIDTH];
        assign w_seg[gi]  = w[gi*SEG_WIDTH +: SEG_WIDTH];
    end
endgenerate

// ============================================================================
// ״̬������
// ============================================================================
localparam [2:0]
    IDLE        = 3'b001,
    COMPUTE     = 3'b010,
    FINALIZE    = 3'b100;

reg [2:0] state, next_state;

// ============================================================================
// Montgomery�˷���ʵ����
// ============================================================================
wire [TOTAL_WIDTH-1:0] mul_result;
wire mul_done;
wire mul_valid;
wire [2*TOTAL_WIDTH-1:0] product = x1 * w;  // 512-bit product

montgomery_pipeline #(
    .TOTAL_BITS(TOTAL_WIDTH),
    .SEG_BITS(SEG_WIDTH),
    .SEG_CNT(SEG_COUNT)
) u_montgomery (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .N(modulus),
    .N_prime(N_prime),
    .t(product),  // 512-bit product: x1 * w
    .mont_result(mul_result),
    .valid_out(mul_valid),
    .done(mul_done)
);

// ============================================================================
// �м����Ĵ���
// ============================================================================
reg [TOTAL_WIDTH-1:0] mul_result_reg;
reg [TOTAL_WIDTH-1:0] x0_reg;
reg [TOTAL_WIDTH-1:0] modulus_reg;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mul_result_reg <= {TOTAL_WIDTH{1'b0}};
        x0_reg <= {TOTAL_WIDTH{1'b0}};
        modulus_reg <= {TOTAL_WIDTH{1'b0}};
    end else if (start) begin
        x0_reg <= x0;
        modulus_reg <= modulus;
    end else if (mul_valid) begin
        mul_result_reg <= mul_result;
    end
end

// ============================================================================
// ģ�Ӽ���ʵ��
// ============================================================================
function automatic [TOTAL_WIDTH-1:0] mod_add;
    input [TOTAL_WIDTH-1:0] a;
    input [TOTAL_WIDTH-1:0] b;
    input [TOTAL_WIDTH-1:0] mod;
    reg [TOTAL_WIDTH:0] sum;
    begin
        sum = a + b;
        mod_add = (sum >= mod) ? (sum - mod) : sum;
    end
endfunction

function automatic [TOTAL_WIDTH-1:0] mod_sub;
    input [TOTAL_WIDTH-1:0] a;
    input [TOTAL_WIDTH-1:0] b;
    input [TOTAL_WIDTH-1:0] mod;
    begin
        mod_sub = (a >= b) ? (a - b) : (a - b + mod);
    end
endfunction

// ============================================================================
// ״̬������
// ============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
        next_state <= IDLE;
        done <= 1'b0;
        busy <= 1'b0;
        result_valid <= 1'b0;
        result_add <= {TOTAL_WIDTH{1'b0}};
        result_sub <= {TOTAL_WIDTH{1'b0}};
    end else begin
        state <= next_state;
        done <= 1'b0;
        result_valid <= 1'b0;

        case(state)
            IDLE: begin
                busy <= 1'b0;
                if (start) begin
                    busy <= 1'b1;
                    next_state <= COMPUTE;
                end
            end

            COMPUTE: begin
                if (mul_valid) begin
                    next_state <= FINALIZE;
                end
            end

            FINALIZE: begin
                result_add <= mod_add(x0_reg, mul_result_reg, modulus_reg);
                result_sub <= mod_sub(x0_reg, mul_result_reg, modulus_reg);
                result_valid <= 1'b1;
                done <= 1'b1;
                busy <= 1'b0;
                next_state <= IDLE;
            end

            default: begin
                next_state <= IDLE;
            end
        endcase
    end
end

endmodule