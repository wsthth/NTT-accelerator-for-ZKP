// ============================================================================
// 文件名: segmented_256bit_full_butterfly.v
// 描述: 256位NTT蝶形运算子核（优化版）
//
// 计算: y0 = (x0 + x1*w) mod N,  y1 = (x0 - x1*w) mod N
//
// 优化点:
//   1. 乘积累加从串行16周期改为组合逻辑1周期
//   2. Montgomery start 使用边沿检测产生单周期脉冲
//   3. 状态机简化为3态，消除冗余等待周期
//   4. 吞吐量: 1结果 / (Montgomery延迟+2) 周期
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
// 数据分段
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
// 16个64位并行乘法器
// ============================================================================
wire [2*SEG_WIDTH-1:0] products [0:SEG_COUNT-1][0:SEG_COUNT-1];

generate
    for (gi = 0; gi < SEG_COUNT; gi = gi + 1) begin : gen_mi
        for (gj = 0; gj < SEG_COUNT; gj = gj + 1) begin : gen_mj
            seg_multiplier_64bit u_mult (
                .a(x1_seg[gi]),
                .b(w_seg[gj]),
                .result(products[gi][gj])
            );
        end
    end
endgenerate

// ============================================================================
// 组合逻辑累加器（always @(*) 阻塞赋值，保证计算顺序）
// ============================================================================
wire [2*TOTAL_WIDTH-1:0] full_product;

reg [SEG_WIDTH-1:0] plo [0:SEG_COUNT-1][0:SEG_COUNT-1];
reg [SEG_WIDTH-1:0] phi [0:SEG_COUNT-1][0:SEG_COUNT-1];
reg [SEG_WIDTH+1:0] o [0:7];
integer ak, ai, aj;

always @(*) begin
    // 拆分乘积为低64位和高64位
    for (ai = 0; ai < SEG_COUNT; ai = ai + 1)
        for (aj = 0; aj < SEG_COUNT; aj = aj + 1) begin
            plo[ai][aj] = products[ai][aj][SEG_WIDTH-1:0];
            phi[ai][aj] = products[ai][aj][2*SEG_WIDTH-1:SEG_WIDTH];
        end

    // 逐段累加，阻塞赋值保证顺序
    o[0] = {2'b0, plo[0][0]};

    o[1] = {2'b0, plo[1][0]} + {2'b0, plo[0][1]}
         + {2'b0, phi[0][0]}
         + {2'b0, o[0][SEG_WIDTH+1:SEG_WIDTH]};

    o[2] = {2'b0, plo[2][0]} + {2'b0, plo[1][1]} + {2'b0, plo[0][2]}
         + {2'b0, phi[1][0]} + {2'b0, phi[0][1]}
         + {2'b0, o[1][SEG_WIDTH+1:SEG_WIDTH]};

    o[3] = {2'b0, plo[3][0]} + {2'b0, plo[2][1]} + {2'b0, plo[1][2]} + {2'b0, plo[0][3]}
         + {2'b0, phi[2][0]} + {2'b0, phi[1][1]} + {2'b0, phi[0][2]}
         + {2'b0, o[2][SEG_WIDTH+1:SEG_WIDTH]};

    o[4] = {2'b0, plo[3][1]} + {2'b0, plo[2][2]} + {2'b0, plo[1][3]}
         + {2'b0, phi[3][0]} + {2'b0, phi[2][1]} + {2'b0, phi[1][2]} + {2'b0, phi[0][3]}
         + {2'b0, o[3][SEG_WIDTH+1:SEG_WIDTH]};

    o[5] = {2'b0, plo[3][2]} + {2'b0, plo[2][3]}
         + {2'b0, phi[3][1]} + {2'b0, phi[2][2]} + {2'b0, phi[1][3]}
         + {2'b0, o[4][SEG_WIDTH+1:SEG_WIDTH]};

    o[6] = {2'b0, plo[3][3]}
         + {2'b0, phi[3][2]} + {2'b0, phi[2][3]}
         + {2'b0, o[5][SEG_WIDTH+1:SEG_WIDTH]};

    o[7] = {2'b0, phi[3][3]}
         + {2'b0, o[6][SEG_WIDTH+1:SEG_WIDTH]};
end

// 输出 512 位乘积
assign full_product = {o[7][SEG_WIDTH-1:0], o[6][SEG_WIDTH-1:0],
                       o[5][SEG_WIDTH-1:0], o[4][SEG_WIDTH-1:0],
                       o[3][SEG_WIDTH-1:0], o[2][SEG_WIDTH-1:0],
                       o[1][SEG_WIDTH-1:0], o[0][SEG_WIDTH-1:0]};

// ============================================================================
// Montgomery 模约简实例
// ============================================================================
reg                     mont_start_r;
reg [2*TOTAL_WIDTH-1:0] mont_t_r;
reg                     mont_start_d;

wire [TOTAL_WIDTH-1:0] montgomery_result;
wire                   montgomery_valid;
wire                   montgomery_done;

// 边沿检测：只在 rising edge 产生单周期脉冲
wire mont_start_pulse = mont_start_r & ~mont_start_d;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        mont_start_d <= 1'b0;
    else
        mont_start_d <= mont_start_r;
end

montgomery_pipeline #(
    .TOTAL_BITS(TOTAL_WIDTH),
    .SEG_BITS(SEG_WIDTH),
    .SEG_CNT(SEG_COUNT),
    .PIPELINE_STAGES(4)
) u_montgomery (
    .clk(clk),
    .rst_n(rst_n),
    .start(mont_start_pulse),
    .N(modulus),
    .N_prime(N_prime),
    .t(mont_t_r),
    .mont_result(montgomery_result),
    .valid_out(montgomery_valid),
    .done(montgomery_done)
);

// ============================================================================
// 保存 x0 供加减法阶段使用
// ============================================================================
reg [TOTAL_WIDTH-1:0] x0_reg;

// ============================================================================
// 完全约简 Montgomery 结果（流水线输出可能在 [0, 2N) 范围）
// ============================================================================
wire [TOTAL_WIDTH-1:0] mont_fully_reduced = (montgomery_result >= modulus)
                                          ? (montgomery_result - modulus)
                                          : montgomery_result;

// ============================================================================
// 加减法结果
// ============================================================================
wire [TOTAL_WIDTH:0] temp_sum = {1'b0, x0_reg} + {1'b0, mont_fully_reduced};
wire [TOTAL_WIDTH-1:0] add_result = (temp_sum >= {1'b0, modulus})
                                  ? (temp_sum - {1'b0, modulus})
                                  : temp_sum[TOTAL_WIDTH-1:0];

wire [TOTAL_WIDTH-1:0] sub_result_raw = ({1'b0, x0_reg} >= {1'b0, mont_fully_reduced})
                                      ? (x0_reg - mont_fully_reduced)
                                      : (x0_reg + modulus - mont_fully_reduced);

wire [TOTAL_WIDTH-1:0] sub_result = (sub_result_raw >= modulus)
                                  ? (sub_result_raw - modulus)
                                  : sub_result_raw;

// ============================================================================
// 状态机（3态: IDLE → MOD_REDUCE → OUTPUT）
// ============================================================================
reg [1:0] state;

localparam [1:0]
    STATE_IDLE       = 2'd0,
    STATE_MOD_REDUCE = 2'd1,
    STATE_OUTPUT     = 2'd2;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state         <= STATE_IDLE;
        done          <= 1'b0;
        busy          <= 1'b0;
        result_add    <= {TOTAL_WIDTH{1'b0}};
        result_sub    <= {TOTAL_WIDTH{1'b0}};
        result_valid  <= 1'b0;
        mont_start_r  <= 1'b0;
        mont_t_r      <= {2*TOTAL_WIDTH{1'b0}};
        x0_reg        <= {TOTAL_WIDTH{1'b0}};
    end else begin
        // 默认拉低
        mont_start_r <= 1'b0;

        case (state)
            STATE_IDLE: begin
                done         <= 1'b0;
                busy         <= 1'b0;
                result_valid <= 1'b0;

                if (start) begin
                    busy         <= 1'b1;
                    mont_start_r <= 1'b1;       // 单周期脉冲（下周期边沿检测生效）
                    mont_t_r     <= full_product; // 锁存组合累加结果
                    x0_reg       <= x0;           // 锁存 x0
                    state        <= STATE_MOD_REDUCE;
                end
            end

            STATE_MOD_REDUCE: begin
                if (montgomery_valid) begin
                    result_add <= add_result;
                    result_sub <= sub_result;
                    state      <= STATE_OUTPUT;
                end
            end

            STATE_OUTPUT: begin
                result_valid <= 1'b1;
                done         <= 1'b1;
                busy         <= 1'b0;
                state        <= STATE_IDLE;
            end

            default: state <= STATE_IDLE;
        endcase
    end
end

endmodule
