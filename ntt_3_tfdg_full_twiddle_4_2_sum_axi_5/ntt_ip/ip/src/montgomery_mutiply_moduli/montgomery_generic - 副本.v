/*
 * 通用型分段蒙哥马利模乘Verilog（适配256/384bit模数）
 * 修复语法错误：384bit M的十六进制表示、参数分隔符、位数匹配
 */
module montgomery_generic #(
    // 参数配置：修改此处切换256/384bit
    parameter TOTAL_BITS    = 256,       // 总位宽：256/384
    parameter SEG_BITS      = 64,        // 分段位宽（固定64bit）
    parameter SEG_CNT       = TOTAL_BITS / SEG_BITS,  // 分段数：4/6
    // -------------------------- 256bit（P-256）常数（十六进制，正确格式） --------------------------
    parameter [TOTAL_BITS-1:0] M       = 256'hFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF,
    parameter [SEG_BITS-1:0]  M_PRIME  = 64'h0000000000000001,  // 示例值（替换为实际P-256的M'）
    parameter [TOTAL_BITS-1:0] R_INV   = 256'h0000000000000001000000000000000000000000000000000000000000000001,  // 示例值
    // -------------------------- 384bit（P-384）常数（启用时注释256bit，取消注释此处） --------------------------
    // parameter [TOTAL_BITS-1:0] M     = 384'h39402006196394479212279040100143613805079739270465446667948293404245721771496870329047266088258938001861606973112319, // 错误：十进制转十六进制！
    // 修正：P-384的标准十六进制表示（正确格式）
    // parameter [TOTAL_BITS-1:0] M     = 384'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFC7634D81F4372DDF581A0DB248B0A77AECEC196ACCC52973,
    // parameter [SEG_BITS-1:0]  M_PRIME= 64'h0000000000000002,  // 示例值（替换为实际P-384的M'）
    // parameter [TOTAL_BITS-1:0] R_INV = 384'h00000000000000010000000000000000000000000000000000000000000000010000000000000000000000000000001,  // 示例值
    // ----------------------------------------------------------------------------------------------
    parameter R             = (1 << SEG_BITS)  // R=2^64（基数）
)(
    input  wire                     clk,          // 系统时钟（建议100MHz）
    input  wire                     rst_n,        // 低电平复位
    input  wire                     valid_in,     // 输入有效
    input  wire [TOTAL_BITS-1:0]    A,            // 输入A（256/384bit）
    input  wire [TOTAL_BITS-1:0]    B,            // 输入B（256/384bit）
    output reg                      valid_out,    // 输出有效
    output reg [TOTAL_BITS-1:0]     mont_result   // 蒙哥马利结果：A×B×R⁻¹ mod M
);

// ===================== 1. 参数合法性校验（编译期） =====================
initial begin
    if (TOTAL_BITS != 256 && TOTAL_BITS != 384) begin
        $error("Error: TOTAL_BITS must be 256 or 384!");
        $finish;
    end
    if (TOTAL_BITS % SEG_BITS != 0) begin
        $error("Error: TOTAL_BITS must be integer multiple of SEG_BITS!");
        $finish;
    end
end

// ===================== 2. 分段拆分（大端序，generate动态生成） =====================
reg [SEG_BITS-1:0] A_seg [SEG_CNT-1:0];  // A分段：[SEG_CNT-1]（高位）~[0]（低位）
reg [SEG_BITS-1:0] B_seg [SEG_CNT-1:0];  // B分段：[SEG_CNT-1]（高位）~[0]（低位）

// 大端序拆分：根据分段数动态生成
generate
    genvar seg_idx;
    for (seg_idx = 0; seg_idx < SEG_CNT; seg_idx = seg_idx + 1) begin : SEG_SPLIT
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                A_seg[seg_idx] <= {SEG_BITS{1'b0}};
                B_seg[seg_idx] <= {SEG_BITS{1'b0}};
            end else if (valid_in) begin
                // 大端序：高位分段对应高地址
                A_seg[seg_idx] <= A[(SEG_CNT-1-seg_idx)*SEG_BITS +: SEG_BITS];
                B_seg[seg_idx] <= B[(SEG_CNT-1-seg_idx)*SEG_BITS +: SEG_BITS];
            end
        end
    end
endgenerate

// ===================== 3. 并行部分积计算（SEG_CNT个64bit乘法器并行） =====================
reg [2*SEG_BITS-1:0] part_product [SEG_CNT-1:0];  // 64×64=128bit部分积
reg                   part_valid;                 // 部分积有效信号

generate
    for (seg_idx = 0; seg_idx < SEG_CNT; seg_idx = seg_idx + 1) begin : PART_PROD
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                part_product[seg_idx] <= {2*SEG_BITS{1'b0}};
            end else if (valid_in) begin
                part_product[seg_idx] <= A_seg[seg_idx] * B_seg[seg_idx];  // 并行乘法
            end
        end
    end
endgenerate

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        part_valid <= 1'b0;
    end else if (valid_in) begin
        part_valid <= 1'b1;
    end else begin
        part_valid <= 1'b0;
    end
end

// ===================== 4. 流水线模约简+递推（动态适配分段数） =====================
reg [TOTAL_BITS-1:0] T [SEG_CNT-1:0];          // 流水线累加器（适配总位宽）
reg [SEG_BITS-1:0]   m [SEG_CNT-1:0];          // 每级约简因子m
reg [SEG_CNT-2:0]    pipe_valid;               // 流水线有效信号（延迟对齐）

// 流水线第0级：初始化+处理第0段
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        T[0] <= {TOTAL_BITS{1'b0}};
        m[0] <= {SEG_BITS{1'b0}};
        if (SEG_CNT > 1) begin
            pipe_valid[0] <= 1'b0;
        end
    end else if (part_valid) begin
        // 累加部分积
        T[0] <= T[0] + part_product[0];
        // 计算m0 = (T0最低64bit × M_PRIME) mod 2^64（等价于取低64bit）
        m[0] <= (T[0][SEG_BITS-1:0] * M_PRIME) & {SEG_BITS{1'b1}};
        if (SEG_CNT > 1) begin
            pipe_valid[0] <= 1'b1;
        end
    end else begin
        if (SEG_CNT > 1) begin
            pipe_valid[0] <= 1'b0;
        end
    end
end

// 流水线中间级：动态生成（适配4/6段）
generate
    for (seg_idx = 1; seg_idx < SEG_CNT-1; seg_idx = seg_idx + 1) begin : PIPE_MID
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                T[seg_idx] <= {TOTAL_BITS{1'b0}};
                m[seg_idx] <= {SEG_BITS{1'b0}};
                pipe_valid[seg_idx] <= 1'b0;
            end else if (pipe_valid[seg_idx-1]) begin
                // 前一段约简：T = (T + m×M) >> 64
                T[seg_idx] <= (T[seg_idx-1] + (m[seg_idx-1] * M)) >> SEG_BITS;
                // 递推累加当前段部分积
                T[seg_idx] <= T[seg_idx] + part_product[seg_idx];
                // 计算当前段约简因子m
                m[seg_idx] <= (T[seg_idx][SEG_BITS-1:0] * M_PRIME) & {SEG_BITS{1'b1}};
                pipe_valid[seg_idx] <= 1'b1;
            end else begin
                pipe_valid[seg_idx] <= 1'b0;
            end
        end
    end
endgenerate

// 流水线最后一级：处理最后一段+最终归一化
reg [TOTAL_BITS-1:0] T_final;
reg                   t_valid;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        T_final <= {TOTAL_BITS{1'b0}};
        t_valid <= 1'b0;
    end else if (SEG_CNT == 1 ? part_valid : pipe_valid[SEG_CNT-2]) begin
        // 最后一段约简
        if (SEG_CNT > 1) begin
            T_final <= (T[SEG_CNT-2] + (m[SEG_CNT-2] * M)) >> SEG_BITS;
        end else begin
            T_final <= T[0];
        end
        // 累加最后一段部分积
        T_final <= T_final + part_product[SEG_CNT-1];
        // 归一化：确保T_final < M
        if (T_final >= M) begin
            T_final <= T_final - M;
        end
        t_valid <= 1'b1;
    end else begin
        t_valid <= 1'b0;
    end
end

// ===================== 5. 结果输出（蒙哥马利最终结果） =====================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mont_result <= {TOTAL_BITS{1'b0}};
        valid_out   <= 1'b0;
    end else if (t_valid) begin
        // 蒙哥马利结果：T_final × R_INV mod M
        mont_result <= (T_final * R_INV) % M;
        valid_out   <= 1'b1;
    end else begin
        valid_out   <= 1'b0;
    end
end

endmodule

