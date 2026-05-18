`timescale 1ns/1ps

// ============================================================================
// 文件名: montgomery_pipeline.v
// 描述: 蒙哥马利乘法流水线模块（支持256位）
//
// 流水线处理分为3个主要阶段:
//   1. start 信号与 valid_in 同步有效
//   2. 计算分为三个主要阶段 stage1_m, stage2_m, stage3_m
//   3. t 信号存储在 t_reg 中
// ============================================================================
module montgomery_pipeline #(
    parameter TOTAL_BITS = 256,
    parameter SEG_BITS  = 64,
    parameter SEG_CNT   = TOTAL_BITS / SEG_BITS,
    parameter PIPELINE_STAGES = 4
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     start,        // valid_in: 乘法开始有效信号
    input  wire [TOTAL_BITS-1:0]    N,
    input  wire [TOTAL_BITS-1:0]    N_prime,
    input  wire [2*TOTAL_BITS-1:0]  t,
    output wire [TOTAL_BITS-1:0]    mont_result,
    output reg                      valid_out,
    output reg                      done
);

// ============================================================================
// 内部变量
// ============================================================================
integer i, j;

// ============================================================================
// Stage 1: 计算 m = (t mod R) * N' mod R
// 注意: valid 信号与 start 同步，start 拉高后开始处理
// ============================================================================
reg                     s1_valid;
reg [TOTAL_BITS-1:0]    s1_t_low;
reg [TOTAL_BITS-1:0]    s1_m;
reg [2*TOTAL_BITS-1:0]  s1_t;         // 保存原始 t 信号
reg [TOTAL_BITS-1:0]    s1_N;
reg [TOTAL_BITS-1:0]    s1_N_prime;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s1_valid   <= 1'b0;
        s1_t_low   <= {TOTAL_BITS{1'b0}};
        s1_m       <= {TOTAL_BITS{1'b0}};
        s1_t       <= {2*TOTAL_BITS{1'b0}};
        s1_N       <= {TOTAL_BITS{1'b0}};
        s1_N_prime <= {TOTAL_BITS{1'b0}};
    end else begin
        s1_valid <= start;
        if (start) begin
            s1_t_low   <= t[TOTAL_BITS-1:0];
            s1_m       <= t[TOTAL_BITS-1:0] * N_prime;
            s1_t       <= t;
            s1_N       <= N;
            s1_N_prime <= N_prime;
        end
    end
end

// ============================================================================
// Stage 2: 分段处理
// 输入: 从 s1_m 和 s1_t 获取数据，来自 Stage1
// ============================================================================
reg                     s2_valid;
reg [SEG_BITS-1:0]      s2_m_seg  [0:SEG_CNT-1];
reg [SEG_BITS-1:0]      s2_N_seg  [0:SEG_CNT-1];
reg [TOTAL_BITS-1:0]    s2_m;
reg [2*TOTAL_BITS-1:0]  s2_t;
reg [TOTAL_BITS-1:0]    s2_N;         // 模数参数 N

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s2_valid <= 1'b0;
        s2_m     <= {TOTAL_BITS{1'b0}};
        s2_t     <= {2*TOTAL_BITS{1'b0}};
        s2_N     <= {TOTAL_BITS{1'b0}};
        for (i = 0; i < SEG_CNT; i = i + 1) begin
            s2_m_seg[i] <= {SEG_BITS{1'b0}};
            s2_N_seg[i] <= {SEG_BITS{1'b0}};
        end
    end else begin
        s2_valid <= s1_valid;
        s2_m     <= s1_m;
        s2_t     <= s1_t;
        s2_N     <= s1_N;
        for (i = 0; i < SEG_CNT; i = i + 1) begin
            s2_m_seg[i] <= s1_m[i*SEG_BITS +: SEG_BITS];
            s2_N_seg[i] <= s1_N[i*SEG_BITS +: SEG_BITS];
        end
    end
end

// ============================================================================
// Stage 3: 将16位x16位64位分段乘法展开
// 输入: 从 s2_m 获取数据，实际上是 s1_m
// ============================================================================
reg                     s3_valid;
reg [2*SEG_BITS-1:0]    s3_products [0:SEG_CNT-1][0:SEG_CNT-1];
reg [TOTAL_BITS-1:0]    s3_m;
reg [2*TOTAL_BITS-1:0]  s3_t;
reg [TOTAL_BITS-1:0]    s3_N;         // 模数参数 N

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s3_valid <= 1'b0;
        s3_m     <= {TOTAL_BITS{1'b0}};
        s3_t     <= {2*TOTAL_BITS{1'b0}};
        s3_N     <= {TOTAL_BITS{1'b0}};
        for (i = 0; i < SEG_CNT; i = i + 1)
            for (j = 0; j < SEG_CNT; j = j + 1)
                s3_products[i][j] <= {2*SEG_BITS{1'b0}};
    end else begin
        s3_valid <= s2_valid;
        s3_m     <= s2_m;
        s3_t     <= s2_t;
        s3_N     <= s2_N;
        for (i = 0; i < SEG_CNT; i = i + 1)
            for (j = 0; j < SEG_CNT; j = j + 1)
                s3_products[i][j] <= s2_m_seg[i] * s2_N_seg[j];
    end
end

// ============================================================================
// Stage 4: 计算 m*N 的累加和
// 注意: 这里使用了进位保留加法器结构
// ============================================================================
reg                     s4_valid;
reg [2*TOTAL_BITS-1:0]  s4_mN;
reg [2*TOTAL_BITS-1:0]  s4_t;
reg [TOTAL_BITS-1:0]    s4_N;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s4_valid <= 1'b0;
        s4_mN    <= {2*TOTAL_BITS{1'b0}};
        s4_t     <= {2*TOTAL_BITS{1'b0}};
        s4_N     <= {TOTAL_BITS{1'b0}};
    end else begin
        s4_valid <= s3_valid;
        s4_t     <= s3_t;
        s4_N     <= s3_N;

        if (s3_valid) begin
            // 使用累加器 (=) 进行部分积累加
            // 这里采用进位保留加法策略减少关键路径
            begin : accum_block
                reg [3*SEG_BITS-1:0] acc [0:2*SEG_CNT-1];  // 192-bit, enough for all carries
                integer ii, jj, pp;

                // 初始化累加器
                for (ii = 0; ii < 2*SEG_CNT; ii = ii + 1)
                    acc[ii] = {(3*SEG_BITS){1'b0}};

                // 按对角线累加部分积到对应位位置
                for (ii = 0; ii < SEG_CNT; ii = ii + 1) begin
                    for (jj = 0; jj < SEG_CNT; jj = jj + 1) begin
                        pp = ii + jj;
                        acc[pp] = acc[pp] + {{(SEG_BITS+2){1'b0}}, s3_products[ii][jj]};
                    end
                end

                // 处理进位传播，将高位进位加到下一位
                for (ii = 0; ii < 2*SEG_CNT - 1; ii = ii + 1) begin
                    acc[ii+1] = acc[ii+1] + {{(2*SEG_BITS){1'b0}}, acc[ii][3*SEG_BITS-1:SEG_BITS]};
                    acc[ii]   = acc[ii] & {{(2*SEG_BITS){1'b0}}, {SEG_BITS{1'b1}}};
                end

                // 将累加器结果写入 s4_mN（只取低 SEG_BITS 位）
                for (ii = 0; ii < 2*SEG_CNT; ii = ii + 1)
                    s4_mN[ii*SEG_BITS +: SEG_BITS] <= acc[ii][SEG_BITS-1:0];
            end
        end
    end
end

// ============================================================================
// Stage 5: Compute sum + output register
//
// Two separate registers:
//   s5_sum  = computation register, updated every cycle from s4
//   out_sum = output register, loaded from s5_sum one cycle later
//
// This prevents s5_sum from overwriting the result before valid_out goes high.
// ============================================================================
reg [2*TOTAL_BITS:0]    s5_sum;
reg                     s5_valid;
reg [TOTAL_BITS-1:0]    s5_N;

// Output registers (one cycle behind computation)
reg [2*TOTAL_BITS:0]    out_sum;
reg [TOTAL_BITS-1:0]    out_N;
reg                     out_valid;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s5_sum    <= {(2*TOTAL_BITS+1){1'b0}};
        s5_valid  <= 1'b0;
        s5_N      <= {TOTAL_BITS{1'b0}};
        out_sum   <= {(2*TOTAL_BITS+1){1'b0}};
        out_N     <= {TOTAL_BITS{1'b0}};
        out_valid <= 1'b0;
        valid_out <= 1'b0;
        done      <= 1'b0;
    end else begin
        // Computation register: load from s4 every cycle
        s5_valid <= s4_valid;
        if (s4_valid) begin
            s5_sum <= s4_t + s4_mN;
            s5_N   <= s4_N;
        end

        // Output register: capture computation result one cycle later
        out_valid <= s5_valid;
        valid_out <= out_valid;
        done      <= out_valid;
        if (s5_valid) begin
            out_sum <= s5_sum;
            out_N   <= s5_N;
        end
    end
end

// Conditional subtract from output register
assign mont_result = (out_sum[2*TOTAL_BITS-1:TOTAL_BITS] >= out_N)
                   ? out_sum[2*TOTAL_BITS-1:TOTAL_BITS] - out_N
                   : out_sum[2*TOTAL_BITS-1:TOTAL_BITS];

endmodule