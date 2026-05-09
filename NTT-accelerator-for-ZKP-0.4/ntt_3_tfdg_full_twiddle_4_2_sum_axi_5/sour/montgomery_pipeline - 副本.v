// ============================================================================
// 文件名: montgomery_pipeline.v
// 描述: 流水线架构的蒙哥马利模约简模块
// ============================================================================
module montgomery_pipeline #(
    parameter TOTAL_BITS = 256,     // 总位宽
    parameter SEG_BITS  = 64,      // 每段位宽
    parameter SEG_CNT   = TOTAL_BITS / SEG_BITS,  // 段数
    parameter PIPELINE_STAGES = 3  // 流水线级数
)(
    input  wire                     clk,          // 时钟
    input  wire                     rst_n,        // 复位(低有效)
    input  wire                     start,        // 开始计算
    input  wire [TOTAL_BITS-1:0]    N,           // 模数
    input  wire [TOTAL_BITS-1:0]    N_prime,     // -N^(-1) mod R
    input  wire [TOTAL_BITS-1:0]    t,           // 输入值 t (2TOTAL_BITS位的一部分)
    output wire [TOTAL_BITS-1:0]    mont_result, // 蒙哥马利约简结果
    output wire                     valid_out,   // 输出有效
    output wire                     done         // 计算完成
);

// ============================================================================
// 内部信号定义
// ============================================================================
reg [PIPELINE_STAGES-1:0] valid_pipeline;
reg [TOTAL_BITS-1:0] mont_result_reg;

// 段输入信号
wire [SEG_BITS-1:0] N_seg [0:SEG_CNT-1];
wire [SEG_BITS-1:0] t_seg [0:2*SEG_CNT-1];  // t可能为2倍位宽

// 流水线寄存器
reg [TOTAL_BITS-1:0] t_reg;
reg [TOTAL_BITS-1:0] N_reg;
reg [TOTAL_BITS-1:0] N_prime_reg;

// ============================================================================
// 分段提取
// ============================================================================
genvar i;
generate
    for (i = 0; i < SEG_CNT; i = i + 1) begin : SEG_EXTRACT
        assign N_seg[i] = N_reg[i*SEG_BITS +: SEG_BITS];
        assign t_seg[i] = t_reg[i*SEG_BITS +: SEG_BITS];
    end
endgenerate

// ============================================================================
// 计算 m = (t mod R) * N' mod R (第一阶段)
// ============================================================================
reg [TOTAL_BITS-1:0] stage1_m;
reg [TOTAL_BITS-1:0] stage1_t_low;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        stage1_m <= {TOTAL_BITS{1'b0}};
        stage1_t_low <= {TOTAL_BITS{1'b0}};
        t_reg <= {TOTAL_BITS{1'b0}};
        N_reg <= {TOTAL_BITS{1'b0}};
        N_prime_reg <= {TOTAL_BITS{1'b0}};
    end else if (start) begin
        // 计算 t mod R (取低TOTAL_BITS位)
        stage1_t_low <= t[TOTAL_BITS-1:0];
        
        // 计算 m = t_low * N_prime mod R
        // 注意：这里简化处理，实际需要完整乘法
        stage1_m <= t[TOTAL_BITS-1:0] * N_prime;
        
        // 寄存输入
        t_reg <= t;
        N_reg <= N;
        N_prime_reg <= N_prime;
    end
end

// ============================================================================
// 分段乘法流水线 (第二阶段)
// ============================================================================
reg [2*SEG_BITS-1:0] stage2_products [0:SEG_CNT-1][0:SEG_CNT-1];
reg [SEG_CNT*SEG_BITS-1:0] stage2_m_seg;
reg [SEG_CNT*SEG_BITS-1:0] stage2_N_seg;
reg stage2_valid;

// 使用integer类型代替int
integer j_int, k_int;  // 用于循环索引

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        stage2_valid <= 1'b0;
        for (j_int = 0; j_int < SEG_CNT; j_int = j_int + 1) begin
            stage2_m_seg[j_int*SEG_BITS +: SEG_BITS] <= {SEG_BITS{1'b0}};
            stage2_N_seg[j_int*SEG_BITS +: SEG_BITS] <= {SEG_BITS{1'b0}};
            for (k_int = 0; k_int < SEG_CNT; k_int = k_int + 1) begin
                stage2_products[j_int][k_int] <= {2*SEG_BITS{1'b0}};
            end
        end
    end else begin
        stage2_valid <= valid_pipeline[0];
        
        // 分段乘法
        for (j_int = 0; j_int < SEG_CNT; j_int = j_int + 1) begin
            stage2_m_seg[j_int*SEG_BITS +: SEG_BITS] <= stage1_m[j_int*SEG_BITS +: SEG_BITS];
            stage2_N_seg[j_int*SEG_BITS +: SEG_BITS] <= N_seg[j_int];
            
            for (k_int = 0; k_int < SEG_CNT; k_int = k_int + 1) begin
                stage2_products[j_int][k_int] <= (stage1_m[j_int*SEG_BITS +: SEG_BITS] * 
                                                 N_seg[k_int]);
            end
        end
    end
end

// ============================================================================
// 累加和进位处理 (第三阶段)
// ============================================================================
reg [SEG_BITS:0] stage3_accum [0:2*SEG_CNT];  // 额外一位用于进位
reg [2*TOTAL_BITS-1:0] stage3_mN;  // m*N结果
reg stage3_valid;
                reg [SEG_BITS-1:0] product_low;
                reg [SEG_BITS-1:0] product_high;

// 使用integer类型
integer pos_temp;  // 临时变量用于存储位置
integer m_int, n_int;  // 循环索引

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        stage3_valid <= 1'b0;
        stage3_mN <= {2*TOTAL_BITS{1'b0}};
        for (j_int = 0; j_int <= 2*SEG_CNT; j_int = j_int + 1) begin
            stage3_accum[j_int] <= {(SEG_BITS+1){1'b0}};
        end
    end else if (stage2_valid) begin
        stage3_valid <= 1'b1;
        
        // 初始化累加器
        for (j_int = 0; j_int <= 2*SEG_CNT; j_int = j_int + 1) begin
            stage3_accum[j_int] <= {(SEG_BITS+1){1'b0}};
        end
        
        // 累加所有乘积
        for (m_int = 0; m_int < SEG_CNT; m_int = m_int + 1) begin
            for (n_int = 0; n_int < SEG_CNT; n_int = n_int + 1) begin
                // 计算位置
                pos_temp = m_int + n_int;
                
                // 累加乘积，需要分成高位和低位
                // 128位乘积拆分为两个64位
                
                product_low = stage2_products[m_int][n_int][SEG_BITS-1:0];
                product_high = stage2_products[m_int][n_int][2*SEG_BITS-1:SEG_BITS];
                
                // 先累加低位
                stage3_accum[pos_temp] = stage3_accum[pos_temp] + product_low;
                
                // 处理低位进位到高位
                if (stage3_accum[pos_temp] > {1'b0, {SEG_BITS{1'b1}}}) begin
                    stage3_accum[pos_temp+1] = stage3_accum[pos_temp+1] + 1'b1;
                    stage3_accum[pos_temp] = stage3_accum[pos_temp] - (1'b1 << SEG_BITS);
                end
                
                // 累加高位
                stage3_accum[pos_temp+1] = stage3_accum[pos_temp+1] + product_high;
            end
        end
        
        // 组合结果
        for (j_int = 0; j_int < 2*SEG_CNT; j_int = j_int + 1) begin
            stage3_mN[j_int*SEG_BITS +: SEG_BITS] <= stage3_accum[j_int][SEG_BITS-1:0];
        end
    end else begin
        stage3_valid <= 1'b0;
    end
end

// ============================================================================
// 最终计算阶段 (第四阶段)
// ============================================================================
reg [2*TOTAL_BITS:0] stage4_sum;  // t + mN
reg [TOTAL_BITS-1:0] stage4_result;
reg stage4_valid;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        stage4_sum <= {(2*TOTAL_BITS+1){1'b0}};
        stage4_result <= {TOTAL_BITS{1'b0}};
        stage4_valid <= 1'b0;
    end else if (stage3_valid) begin
        stage4_valid <= 1'b1;
        
        // 计算 t + mN
        stage4_sum <= t_reg + stage3_mN;
        
        // 计算 (t + mN) / R (右移TOTAL_BITS位)
        stage4_result <= stage4_sum[2*TOTAL_BITS-1:TOTAL_BITS];
        
        // 最终约简: 如果结果 >= N，则减去N
        if (stage4_sum[2*TOTAL_BITS-1:TOTAL_BITS] >= N_reg) begin
            mont_result_reg <= stage4_sum[2*TOTAL_BITS-1:TOTAL_BITS] - N_reg;
        end else begin
            mont_result_reg <= stage4_sum[2*TOTAL_BITS-1:TOTAL_BITS];
        end
    end else begin
        stage4_valid <= 1'b0;
    end
end

// ============================================================================
// 流水线控制
// ============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        valid_pipeline <= {PIPELINE_STAGES{1'b0}};
    end else begin
        valid_pipeline[0] <= start;
        for (j_int = 1; j_int < PIPELINE_STAGES; j_int = j_int + 1) begin
            valid_pipeline[j_int] <= valid_pipeline[j_int-1];
        end
    end
end

// ============================================================================
// 输出赋值
// ============================================================================
assign mont_result = mont_result_reg;
assign valid_out = stage4_valid;
assign done = stage4_valid;

endmodule
