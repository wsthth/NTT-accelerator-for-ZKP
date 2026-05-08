// ============================================================================
// 文件名: montgomery_pipeline.v
// 描述: 流水线架构的蒙哥马利模约简模块
// 修正说明:
// 1. 修正了int类型为integer类型
// 2. 移除了automatic变量，使用普通变量
// 3. 修正了累加逻辑的错误
// 4. 优化了流水线控制
// ============================================================================
module montgomery_pipeline #(
    parameter TOTAL_BITS = 256,     // 总位宽
    parameter SEG_BITS  = 64,      // 每段位宽
    parameter SEG_CNT   = TOTAL_BITS / SEG_BITS,  // 段数
    parameter PIPELINE_STAGES = 4  // 流水线级数
)(
    input  wire                     clk,          // 时钟
    input  wire                     rst_n,        // 复位(低有效)
    input  wire                     start,        // 开始计算
    input  wire [TOTAL_BITS-1:0]    N,           // 模数
    input  wire [TOTAL_BITS-1:0]    N_prime,     // -N^(-1) mod R
    input  wire [2*TOTAL_BITS-1:0]  t,           // 输入值 t (512位，a_mont * b_mont)
    output wire  [TOTAL_BITS-1:0]    mont_result, // 蒙哥马利约简结果
    output reg                      valid_out,   // 输出有效
    output reg                      done         // 计算完成
);

// ============================================================================
// 内部信号定义
// ============================================================================
reg [PIPELINE_STAGES-1:0] valid_pipeline;

// 流水线寄存器
reg [2*TOTAL_BITS-1:0] t_reg;        // 512位
reg [TOTAL_BITS-1:0] N_reg;
reg [TOTAL_BITS-1:0] N_prime_reg;

// 第一阶段：计算 m = (t mod R) * N' mod R
reg [TOTAL_BITS-1:0] stage1_t_low;
reg [TOTAL_BITS-1:0] stage1_m;
reg stage1_valid;

// 第二阶段：分段乘法准备
reg [SEG_BITS-1:0] stage2_m_seg [0:SEG_CNT-1];
reg [SEG_BITS-1:0] stage2_N_seg [0:SEG_CNT-1];
reg stage2_valid;

// 第三阶段：分段乘法
reg [2*SEG_BITS-1:0] stage3_products [0:SEG_CNT-1][0:SEG_CNT-1];
reg [TOTAL_BITS-1:0] stage3_m_reg;
reg stage3_valid;

// 第四阶段：累加
reg [2*TOTAL_BITS-1:0] stage4_mN;  // m * N 的结果
reg stage4_valid;

// 第五阶段：最终计算
reg [2*TOTAL_BITS:0] stage5_sum;   // t + mN，可能进位一位
reg stage5_valid;

// 循环索引变量
integer i, j;

// ============================================================================
// 第一阶段：计算 m = (t mod R) * N' mod R
// ============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        stage1_t_low <= {TOTAL_BITS{1'b0}};
        stage1_m <= {TOTAL_BITS{1'b0}};
        stage1_valid <= 1'b0;
        t_reg <= {2*TOTAL_BITS{1'b0}};
        N_reg <= {TOTAL_BITS{1'b0}};
        N_prime_reg <= {TOTAL_BITS{1'b0}};
    end else if (start) begin
        // t mod R：取t的低TOTAL_BITS位
        stage1_t_low <= t[TOTAL_BITS-1:0];
        
        // m = (t mod R) * N' mod R
        // 这里我们计算完整的乘积，然后取低TOTAL_BITS位
        stage1_m <= (t[TOTAL_BITS-1:0] * N_prime);
        
        stage1_valid <= 1'b1;
        
        // 寄存输入
        t_reg <= t;
        N_reg <= N;
        N_prime_reg <= N_prime;
    end else begin
        stage1_valid <= 1'b0;
    end
end

// ============================================================================
// 第二阶段：准备分段数据
// ============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        stage2_valid <= 1'b0;
        for (i = 0; i < SEG_CNT; i = i + 1) begin
            stage2_m_seg[i] <= {SEG_BITS{1'b0}};
            stage2_N_seg[i] <= {SEG_BITS{1'b0}};
        end
    end else if (stage1_valid) begin
        stage2_valid <= 1'b1;
        
        // 将m和N分解为分段
        for (i = 0; i < SEG_CNT; i = i + 1) begin
            stage2_m_seg[i] <= stage1_m[i*SEG_BITS +: SEG_BITS];
            stage2_N_seg[i] <= N_reg[i*SEG_BITS +: SEG_BITS];
        end
    end else begin
        stage2_valid <= 1'b0;
    end
end

// ============================================================================
// 第三阶段：分段乘法
// ============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        stage3_valid <= 1'b0;
        stage3_m_reg <= {TOTAL_BITS{1'b0}};
        for (i = 0; i < SEG_CNT; i = i + 1) begin
            for (j = 0; j < SEG_CNT; j = j + 1) begin
                stage3_products[i][j] <= {2*SEG_BITS{1'b0}};
            end
        end
    end else if (stage2_valid) begin
        stage3_valid <= 1'b1;
        stage3_m_reg <= stage1_m;  // 传递m值
        
        // 执行分段乘法--16个64位乘法器并行工作
        for (i = 0; i < SEG_CNT; i = i + 1) begin
            for (j = 0; j < SEG_CNT; j = j + 1) begin
                stage3_products[i][j] <= stage2_m_seg[i] * stage2_N_seg[j];//th--关键路径：64位乘法
            end
        end
    end else begin
        stage3_valid <= 1'b0;
    end
end

// ============================================================================
// 第四阶段：累加分段乘法结果
// ============================================================================
reg [SEG_BITS:0] accum [0:2*SEG_CNT-1];  // 每个位置需要SEG_BITS+1位以处理进位
integer pos_temp;
                reg [SEG_BITS-1:0] prod_low;
                reg [SEG_BITS-1:0] prod_high;
                reg [SEG_BITS:0] temp_sum;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        stage4_valid <= 1'b0;
        stage4_mN <= {2*TOTAL_BITS{1'b0}};
        for (i = 0; i < 2*SEG_CNT; i = i + 1) begin
            accum[i] <= {(SEG_BITS+1){1'b0}};
        end
    end else if (stage3_valid) begin
        stage4_valid <= 1'b1;
        
        // 初始化累加器
        for (i = 0; i < 2*SEG_CNT; i = i + 1) begin
            accum[i] <= {(SEG_BITS+1){1'b0}};
        end
        
        // 累加所有乘积
        for (i = 0; i < SEG_CNT; i = i + 1) begin
            for (j = 0; j < SEG_CNT; j = j + 1) begin
                // 计算位置
                pos_temp = i + j;
                
                // 将128位乘积拆分为两个64位部分
                
                prod_low = stage3_products[i][j][SEG_BITS-1:0];
                prod_high = stage3_products[i][j][2*SEG_BITS-1:SEG_BITS];
                
                // 累加低位
                temp_sum = accum[pos_temp] + prod_low;
                accum[pos_temp] = temp_sum[SEG_BITS-1:0];
                
                // 处理进位
                if (temp_sum[SEG_BITS]) begin
                    accum[pos_temp+1] = accum[pos_temp+1] + 1'b1;
                end
                
                // 累加高位
                accum[pos_temp+1] = accum[pos_temp+1] + prod_high;
            end
        end
        
        // 组合结果得到 mN
        for (i = 0; i < 2*SEG_CNT; i = i + 1) begin
            stage4_mN[i*SEG_BITS +: SEG_BITS] <= accum[i][SEG_BITS-1:0];//th--关键路径：64位乘法
        end
    end else begin
        stage4_valid <= 1'b0;
    end
end

// ============================================================================
// 第五阶段：最终计算
// ============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        stage5_sum <= {(2*TOTAL_BITS+1){1'b0}};
        stage5_valid <= 1'b0;
        // mont_result <= {TOTAL_BITS{1'b0}};
        valid_out <= 1'b0;
        done <= 1'b0;
    end else if (stage4_valid) begin
        stage5_valid <= 1'b1;
        
        // 计算 t + mN
        stage5_sum <= t_reg + stage4_mN;
        
        // 计算 (t + mN) / R (右移TOTAL_BITS位)
        // mont_result <= stage5_sum[2*TOTAL_BITS-1:TOTAL_BITS];
        
        // 最终约简：如果结果 >= N，则减去N
/*         if (stage5_sum[2*TOTAL_BITS-1:TOTAL_BITS] >= N_reg) begin
            mont_result <= stage5_sum[2*TOTAL_BITS-1:TOTAL_BITS] - N_reg;
            
        end
 */        
        valid_out <= 1'b1;
        done <= 1'b1;
    end else begin
        stage5_valid <= 1'b0;
        valid_out <= 1'b0;
        done <= 1'b0;
    end
end
        assign mont_result = (stage5_sum[2*TOTAL_BITS-1:TOTAL_BITS] >= N_reg)?stage5_sum[2*TOTAL_BITS-1:TOTAL_BITS] - N_reg:stage5_sum[2*TOTAL_BITS-1:TOTAL_BITS];
// ============================================================================
// 流水线控制
// ============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        valid_pipeline <= {PIPELINE_STAGES{1'b0}};
    end else begin
        valid_pipeline[0] <= start;
        for (i = 1; i < PIPELINE_STAGES; i = i + 1) begin
            valid_pipeline[i] <= valid_pipeline[i-1];
        end
    end
end

// ============================================================================
// 调试输出（仅用于仿真）
// ============================================================================
// synthesis translate_off

/* reg [TOTAL_BITS-1:0] debug_t_low;
reg [TOTAL_BITS-1:0] debug_m;
reg [2*TOTAL_BITS-1:0] debug_mN;
reg [2*TOTAL_BITS:0] debug_sum;
integer cycle_count;

initial begin
    cycle_count = 0;
end

always @(posedge clk) begin
    if (!rst_n) begin
        cycle_count <= 0;
    end else begin
        cycle_count <= cycle_count + 1;
        
        if (start) begin
            $display("[DEBUG] Cycle %0d: start computing", cycle_count);
            $display("[DEBUG] t = 0x%h... (512bit)", t);
            $display("[DEBUG] N = 0x%h", N);
            $display("[DEBUG] N_prime = 0x%h", N_prime);
        end
        
        if (stage1_valid) begin
            debug_t_low <= stage1_t_low;
            debug_m <= stage1_m;
            $display("[DEBUG] Cycle %0d: Stage1 - t_low = 0x%h, m = 0x%h", 
                     cycle_count, stage1_t_low, stage1_m);
        end
        
        if (stage3_valid) begin
            $display("[DEBUG] Cycle %0d: Stage3 - segment muti complete", cycle_count);
        end
        
        if (stage4_valid) begin
            debug_mN <= stage4_mN;
            $display("[DEBUG] Cycle %0d: Stage4 - mN = 0x%h... (512bit)", 
                     cycle_count, stage4_mN);
        end
        
        if (stage5_valid) begin
            debug_sum <= stage5_sum;
            $display("[DEBUG] Cycle %0d: Stage5 - final_result = 0x%h", 
                     cycle_count, mont_result);
            $display("[DEBUG]                    t + mN = 0x%h... (513bit)", debug_sum);
            $display("[DEBUG]                    (t + mN) >> %0d = 0x%h", 
                     TOTAL_BITS, stage5_sum[2*TOTAL_BITS-1:TOTAL_BITS]);
        end
        
        if (valid_out) begin
            $display("[DEBUG] Cycle %0d: compute complete,result = 0x%h", 
                     cycle_count, mont_result);
        end
    end
end
 */// synthesis translate_on

endmodule