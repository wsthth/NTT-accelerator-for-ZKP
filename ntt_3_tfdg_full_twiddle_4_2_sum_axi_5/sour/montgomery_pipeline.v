// ============================================================================
// 文件名: montgomery_pipeline.v
// 描述: 流式流水线架构的蒙哥马利模约简模块
// 特点: 真正流水线设计，满负载后每个周期出一个结果
// ============================================================================
module montgomery_pipeline #(
    parameter TOTAL_BITS = 256,     // 总位宽
    parameter SEG_BITS  = 64,      // 每段位宽
    parameter SEG_CNT   = TOTAL_BITS / SEG_BITS,  // 段数 = 4
    parameter PIPELINE_STAGES = 6  // 流水线级数
)(
    input  wire                     clk,          // 时钟
    input  wire                     rst_n,        // 复位(低有效)

    // 输入接口 (ready/valid 握手)
    input  wire [TOTAL_BITS-1:0]    N,           // 模数
    input  wire [TOTAL_BITS-1:0]    N_prime,     // -N^(-1) mod R
    input  wire [2*TOTAL_BITS-1:0]  t,           // 输入值 t (512位)
    input  wire                     in_valid,    // 输入有效
    output wire                     in_ready,    // 输入就绪（可接收新数据）

    // 输出接口 (ready/valid 握手)
    output wire [TOTAL_BITS-1:0]    mont_result, // 蒙哥马利约简结果
    output wire                     out_valid    // 输出有效
);

localparam STAGE1 = 0;
localparam STAGE2 = 1;
localparam STAGE3 = 2;
localparam STAGE4 = 3;
localparam STAGE5 = 4;
localparam STAGE6 = 5;

reg [PIPELINE_STAGES-1:0] stage_valid;
reg out_ready;
integer i;

// ============================================================================
// Stage 1: 计算 m = (t mod R) * N' mod R
// ============================================================================
reg [TOTAL_BITS-1:0] stage1_m;
reg [TOTAL_BITS-1:0] stage1_N;
reg [TOTAL_BITS-1:0] stage1_N_prime;
reg [2*TOTAL_BITS-1:0] stage1_t;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        stage1_m <= {TOTAL_BITS{1'b0}};
        stage1_N <= {TOTAL_BITS{1'b0}};
        stage1_N_prime <= {TOTAL_BITS{1'b0}};
        stage1_t <= {2*TOTAL_BITS{1'b0}};
        stage_valid[STAGE1] <= 1'b0;
    end else if (in_valid && in_ready) begin
        stage1_m <= (t[TOTAL_BITS-1:0] * N_prime);
        stage1_N <= N;
        stage1_N_prime <= N_prime;
        stage1_t <= t;
        stage_valid[STAGE1] <= 1'b1;
    end else begin
        stage_valid[STAGE1] <= 1'b0;
    end
end

// ============================================================================
// Stage 2: 分段准备
// ============================================================================
reg [SEG_BITS-1:0] stage2_m_seg [0:SEG_CNT-1];
reg [SEG_BITS-1:0] stage2_N_seg [0:SEG_CNT-1];
reg [2*TOTAL_BITS-1:0] stage2_t;
reg [TOTAL_BITS-1:0] stage2_N;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        stage2_t <= {2*TOTAL_BITS{1'b0}};
        stage2_N <= {TOTAL_BITS{1'b0}};
        for (i = 0; i < SEG_CNT; i = i + 1) begin
            stage2_m_seg[i] <= {SEG_BITS{1'b0}};
            stage2_N_seg[i] <= {SEG_BITS{1'b0}};
        end
        stage_valid[STAGE2] <= 1'b0;
    end else if (stage_valid[STAGE1]) begin
        stage2_t <= stage1_t;
        stage2_N <= stage1_N;
        for (i = 0; i < SEG_CNT; i = i + 1) begin
            stage2_m_seg[i] <= stage1_m[i*SEG_BITS +: SEG_BITS];
            stage2_N_seg[i] <= stage1_N[i*SEG_BITS +: SEG_BITS];
        end
        stage_valid[STAGE2] <= 1'b1;
    end else begin
        stage_valid[STAGE2] <= 1'b0;
    end
end

// ============================================================================
// Stage 3: 分段乘法 (16个64位乘法器并行)
// ============================================================================
reg [2*SEG_BITS-1:0] stage3_products [0:SEG_CNT-1][0:SEG_CNT-1];
reg [2*TOTAL_BITS-1:0] stage3_t;
reg [TOTAL_BITS-1:0] stage3_N;
integer j;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        stage3_t <= {2*TOTAL_BITS{1'b0}};
        stage3_N <= {TOTAL_BITS{1'b0}};
        for (i = 0; i < SEG_CNT; i = i + 1) begin
            for (j = 0; j < SEG_CNT; j = j + 1) begin
                stage3_products[i][j] <= {2*SEG_BITS{1'b0}};
            end
        end
        stage_valid[STAGE3] <= 1'b0;
    end else if (stage_valid[STAGE2]) begin
        stage3_t <= stage2_t;
        stage3_N <= stage2_N;
        for (i = 0; i < SEG_CNT; i = i + 1) begin
            for (j = 0; j < SEG_CNT; j = j + 1) begin
                stage3_products[i][j] <= stage2_m_seg[i] * stage2_N_seg[j];
            end
        end
        stage_valid[STAGE3] <= 1'b1;
    end else begin
        stage_valid[STAGE3] <= 1'b0;
    end
end

// ============================================================================
// Stage 4: 累加 (使用组合逻辑计算 + 时序寄存器输出)
// ============================================================================
reg [2*TOTAL_BITS-1:0] stage4_mN;
reg [2*TOTAL_BITS-1:0] stage4_t;
reg [TOTAL_BITS-1:0] stage4_N;

wire [2*TOTAL_BITS-1:0] stage4_mN_comb;
reg [SEG_BITS:0] stage4_accum_comb [0:7];
integer stage4_row, stage4_col, stage4_pos;

always @(*) begin
    for (stage4_pos = 0; stage4_pos < 8; stage4_pos = stage4_pos + 1) begin
        stage4_accum_comb[stage4_pos] = 0;
    end
    
    for (stage4_row = 0; stage4_row < SEG_CNT; stage4_row = stage4_row + 1) begin
        for (stage4_col = 0; stage4_col < SEG_CNT; stage4_col = stage4_col + 1) begin
            stage4_pos = stage4_row + stage4_col;
            stage4_accum_comb[stage4_pos] = stage4_accum_comb[stage4_pos] + stage3_products[stage4_row][stage4_col][SEG_BITS-1:0];
            stage4_accum_comb[stage4_pos+1] = stage4_accum_comb[stage4_pos+1] + stage3_products[stage4_row][stage4_col][2*SEG_BITS-1:SEG_BITS];
        end
    end
end

assign stage4_mN_comb = {
    stage4_accum_comb[7][SEG_BITS-1:0],
    stage4_accum_comb[6][SEG_BITS-1:0],
    stage4_accum_comb[5][SEG_BITS-1:0],
    stage4_accum_comb[4][SEG_BITS-1:0],
    stage4_accum_comb[3][SEG_BITS-1:0],
    stage4_accum_comb[2][SEG_BITS-1:0],
    stage4_accum_comb[1][SEG_BITS-1:0],
    stage4_accum_comb[0][SEG_BITS-1:0]
};

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        stage4_mN <= {2*TOTAL_BITS{1'b0}};
        stage4_t <= {2*TOTAL_BITS{1'b0}};
        stage4_N <= {TOTAL_BITS{1'b0}};
        stage_valid[STAGE4] <= 1'b0;
    end else if (stage_valid[STAGE3]) begin
        stage4_t <= stage3_t;
        stage4_N <= stage3_N;
        stage4_mN <= stage4_mN_comb;
        stage_valid[STAGE4] <= 1'b1;
    end else begin
        stage_valid[STAGE4] <= 1'b0;
    end
end

// ============================================================================
// Stage 5: 最终计算 (t + mN)
// ============================================================================
reg [2*TOTAL_BITS:0] stage5_sum;
reg [TOTAL_BITS-1:0] stage5_N;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        stage5_sum <= 0;
        stage5_N <= {TOTAL_BITS{1'b0}};
        stage_valid[STAGE5] <= 1'b0;
    end else if (stage_valid[STAGE4]) begin
        stage5_sum <= stage4_t + stage4_mN;
        stage5_N <= stage4_N;
        stage_valid[STAGE5] <= 1'b1;
    end else begin
        stage_valid[STAGE5] <= 1'b0;
    end
end

// ============================================================================
// Stage 6: 最终约简 (t + mN) / R，并判断是否需要减N
// ============================================================================
reg [TOTAL_BITS-1:0] stage6_result;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        stage6_result <= {TOTAL_BITS{1'b0}};
        stage_valid[STAGE6] <= 1'b0;
    end else if (stage_valid[STAGE5]) begin
        if (stage5_sum[2*TOTAL_BITS-1:TOTAL_BITS] >= stage5_N)
            stage6_result <= stage5_sum[2*TOTAL_BITS-1:TOTAL_BITS] - stage5_N;
        else
            stage6_result <= stage5_sum[2*TOTAL_BITS-1:TOTAL_BITS];
        stage_valid[STAGE6] <= 1'b1;
    end else begin
        stage_valid[STAGE6] <= 1'b0;
    end
end

// ============================================================================
// 握手控制
// ============================================================================
assign in_ready = !stage_valid[STAGE1] || out_ready;
assign out_valid = stage_valid[STAGE6];
assign mont_result = stage6_result;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        out_ready <= 1'b1;
    end else begin
        if (out_valid && !out_ready)
            out_ready <= 1'b0;
        else if (out_ready)
            out_ready <= 1'b1;
    end
end

endmodule
