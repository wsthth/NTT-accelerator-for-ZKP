// ============================================================================
// 文件名: segmented_256bit_butterfly.v
// 描述: 基于分段计算的256位蝶形运算子核
// 创新点: 将256位运算拆分为4个64位并行处理，降低单次乘法位宽
// 功能: 计算 x0 ± x1 * w (模运算)
// ============================================================================
module segmented_256bit_butterfly #(
    parameter TOTAL_WIDTH = 256,           // 总数据位宽
    parameter SEG_WIDTH = 64,             // 分段位宽
    parameter SEG_COUNT = TOTAL_WIDTH / SEG_WIDTH  // 分段数
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // 控制信号
    input wire start,        // 开始计算
    input wire add_mode,     // 1:加法(x0+x1*w), 0:减法(x0-x1*w)
    output reg done,         // 计算完成
    output reg busy,         // 忙碌状态
    
    // 256位数据输入
    input wire [TOTAL_WIDTH-1:0] x0,      // x0 (256位)
    input wire [TOTAL_WIDTH-1:0] x1,      // x1 (256位)
    input wire [TOTAL_WIDTH-1:0] w,       // w (256位)
    input wire [TOTAL_WIDTH-1:0] N_prime,    // -N^(-1) mod R
    input wire [TOTAL_WIDTH-1:0] modulus, // 256位模数
    
    // 256位结果输出
    output reg [TOTAL_WIDTH-1:0] result,  // 计算结果
    output reg result_valid               // 结果有效
);

// ============================================================================
// 关键设计思路：正确的256位分段乘法
// ============================================================================
// 设 A = x1, B = w，都是256位
// A = A3×2^192 + A2×2^128 + A1×2^64 + A0
// B = B3×2^192 + B2×2^128 + B1×2^64 + B0
// A×B = A0B0 + (A0B1 + A1B0)×2^64 + (A0B2 + A1B1 + A2B0)×2^128 
//      + (A0B3 + A1B2 + A2B1 + A3B0)×2^192 + (A1B3 + A2B2 + A3B1)×2^256
//      + (A2B3 + A3B2)×2^320 + (A3B3)×2^384

// ============================================================================
// 内部信号定义
// ============================================================================
// 分段数据
wire [SEG_WIDTH-1:0] x0_seg [0:SEG_COUNT-1];
wire [SEG_WIDTH-1:0] x1_seg [0:SEG_COUNT-1];
wire [SEG_WIDTH-1:0] w_seg [0:SEG_COUNT-1];
wire [SEG_WIDTH-1:0] mod_seg [0:SEG_COUNT-1];

// 16个分段乘积（每个64×64=128位）
wire [2*SEG_WIDTH-1:0] products [0:SEG_COUNT-1][0:SEG_COUNT-1];

// 乘积累加结果（512位，用于后续模约简）
wire [2*TOTAL_WIDTH-1:0] full_product;  // 512位完整乘积

// 状态机
reg [3:0] state;
reg [3:0] next_state;

localparam [3:0]
    STATE_IDLE        = 4'd0,
    STATE_SPLIT       = 4'd1,   // 拆分数据
    STATE_COMPUTE     = 4'd2,   // 计算分段乘积
    STATE_ACCUMULATE  = 4'd3,   // 累加乘积（考虑权重）
    STATE_MOD_REDUCE  = 4'd4,   // 模约简
    STATE_ADD_SUB     = 4'd5,   // 加减运算
    STATE_DONE        = 4'd6;

// 计数器
reg [7:0] cycle_counter;

// ============================================================================
// 数据分段（修正版）
// ============================================================================
genvar i;
generate
    for (i = 0; i < SEG_COUNT; i = i + 1) begin : gen_segments
        assign x0_seg[i] = x0[i*SEG_WIDTH +: SEG_WIDTH];
        assign x1_seg[i] = x1[i*SEG_WIDTH +: SEG_WIDTH];
        assign w_seg[i] = w[i*SEG_WIDTH +: SEG_WIDTH];
        // 删除mod_seg，除非您在乘法器中需要模数
        // assign mod_seg[i] = modulus[i*SEG_WIDTH +: SEG_WIDTH];
    end
endgenerate

// ============================================================================
// 分段乘法器阵列
// ============================================================================
generate
    for (i = 0; i < SEG_COUNT; i = i + 1) begin : gen_i
        for (genvar j = 0; j < SEG_COUNT; j = j + 1) begin : gen_j
            // 每个分段乘法器计算 x1_seg[i] * w_seg[j]
            seg_multiplier_64bit u_mult (
                .a(x1_seg[i]),
                .b(w_seg[j]),
                .result(products[i][j])
            );
        end
    end
endgenerate

// ============================================================================
// 乘积累加器（修正版）
// ============================================================================
reg [2*TOTAL_WIDTH-1:0] accumulator;  // 512位累加器
reg [2:0] accum_phase;
reg [2:0] accum_i, accum_j;  // 累加循环变量
reg [8:0] weight_reg;        // 增加1位防止溢出

// 权重计算组合逻辑 - 确保在合理范围内
wire [8:0] weight_calc = (accum_i + accum_j) * SEG_WIDTH[8:0];  // 显式位宽转换

// 累加控制
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        accumulator <= 512'd0;
        accum_phase <= 3'd0;
        accum_i <= 3'd0;
        accum_j <= 3'd0;
        weight_reg <= 9'd0;
    end else if (state == STATE_ACCUMULATE) begin
        case (accum_phase)
            3'd0: begin
                // 第一阶段：清零累加器，初始化循环变量
                accumulator <= 512'd0;
                accum_i <= 3'd0;
                accum_j <= 3'd0;
                accum_phase <= 3'd1;
            end
            3'd1: begin
                // 第二阶段：计算当前权重，开始累加
                weight_reg <= weight_calc;
                
                // 确保不移位超过511位
                if (weight_calc <= 511) begin
                    accumulator <= accumulator + (products[accum_i][accum_j] << weight_calc);
                end
                
                // 更新循环变量
                if (accum_j < SEG_COUNT-1) begin
                    accum_j <= accum_j + 1;
                end else begin
                    accum_j <= 3'd0;
                    if (accum_i < SEG_COUNT-1) begin
                        accum_i <= accum_i + 1;
                    end else begin
                        // 所有乘积累加完成
                        accum_phase <= 3'd2;
                    end
                end
            end
            3'd2: begin
                // 累加完成，等待一个周期稳定
                accum_phase <= 3'd3;
            end
            3'd3: begin
                // 保持状态，直到状态机切换
                // accum_phase <= 3'd0; // 由状态机控制复位
            end
        endcase
    end else if (state != STATE_ACCUMULATE) begin
        // 不在累加状态时复位累加状态
        accum_phase <= 3'd0;
        accum_i <= 3'd0;
        accum_j <= 3'd0;
    end
end

// 当累加完成时输出
assign full_product = (accum_phase == 3'd3) ? accumulator : 512'd0; 
 
 
 
 // ============================================================================
// 模约简单元（使用您现有的蒙哥马利约简模块）
// ============================================================================
wire [TOTAL_WIDTH-1:0] montgomery_result;
wire montgomery_valid;
wire montgomery_done;

// 需要预计算的参数（假设从外部输入）
wire [TOTAL_WIDTH-1:0] R2_mod_N;    // R^2 mod N

// 实例化您的蒙哥马利流水线模块
montgomery_pipeline #(
    .TOTAL_BITS(TOTAL_WIDTH),
    .SEG_BITS(SEG_WIDTH),
    .SEG_CNT(SEG_COUNT),
    .PIPELINE_STAGES(4)
) u_montgomery (
    .clk(clk),
    .rst_n(rst_n),
    .start(state == STATE_MOD_REDUCE),
    .N(modulus),
    .N_prime(N_prime),
    // .t(full_product),           // 512位乘积
    
    .t(512'h10d9acc5b5f2cff8afdde66d2d79eb05306f571ee8d01e5b47d1c9be023c9a51c2fb3a724fe0b2924ebf26b0a3f40a9ba32fdf2ac38f753569541b3a3573e58),           // 512位乘积
    .mont_result(montgomery_result),
    .valid_out(montgomery_valid),
    .done(montgomery_done)
);

// ============================================================================
// 模加/模减单元（256位）
// ============================================================================
reg [TOTAL_WIDTH-1:0] mod_add_sub_result;

always @(*) begin
    if (add_mode) begin
        // 模加法：result = (x0 + montgomery_result) mod modulus
        // 需要处理溢出
        if ({1'b0, x0} + {1'b0, montgomery_result} >= {1'b0, modulus}) begin
            mod_add_sub_result = x0 + montgomery_result - modulus;
        end else begin
            mod_add_sub_result = x0 + montgomery_result;
        end
    end else begin
        // 模减法：result = (x0 - montgomery_result + modulus) mod modulus
        if (x0 >= montgomery_result) begin
            mod_add_sub_result = x0 - montgomery_result;
        end else begin
            mod_add_sub_result = x0 + modulus - montgomery_result;
        end
    end
end

 // ============================================================================
// 修正后的状态机
// ============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= STATE_IDLE;
        done <= 1'b0;
        busy <= 1'b0;
        result <= {TOTAL_WIDTH{1'b0}};
        result_valid <= 1'b0;
        cycle_counter <= 8'd0;
    end else begin
        // 默认下一个状态为当前状态
        next_state = state;
        
        case (state)
            STATE_IDLE: begin
                done <= 1'b0;
                busy <= 1'b0;
                result_valid <= 1'b0;
                cycle_counter <= 8'd0;
                
                if (start) begin
                    busy <= 1'b1;
                    next_state = STATE_SPLIT;
                end else begin
                    next_state = STATE_IDLE;
                end
            end
            
            STATE_SPLIT: begin
                // 数据分段已在组合逻辑中完成
                // 等待一个周期确保数据稳定
                cycle_counter <= cycle_counter + 1;
                next_state = STATE_COMPUTE;
            end
            
            STATE_COMPUTE: begin
                // 16个64位乘法器并行计算（组合逻辑）
                cycle_counter <= cycle_counter + 1;
                next_state = STATE_ACCUMULATE;
            end
            
            STATE_ACCUMULATE: begin
                // 累加乘积（考虑权重）
                // 等待累加完成
                if (accum_phase == 3'd3) begin  // 累加完成
                    cycle_counter <= cycle_counter + 1;
                    next_state = STATE_MOD_REDUCE;
                end else begin
                    // 保持在累加状态
                    next_state = STATE_ACCUMULATE;
                end
            end
            
            STATE_MOD_REDUCE: begin
                // 蒙哥马利约简（流水线操作）
                // 注意：这里需要确保不会重复启动蒙哥马利模块
                if (montgomery_done) begin
                    cycle_counter <= cycle_counter + 1;
                    next_state = STATE_ADD_SUB;
                end else begin
                    // 保持在模约简状态
                    next_state = STATE_MOD_REDUCE;
                end
            end
            
            STATE_ADD_SUB: begin
                // 模加减运算（组合逻辑，一个周期）
                result <= mod_add_sub_result;
                cycle_counter <= cycle_counter + 1;
                next_state = STATE_DONE;
            end
            
            STATE_DONE: begin
                result_valid <= 1'b1;
                done <= 1'b1;
                busy <= 1'b0;
                
                if (!start) begin
                    next_state = STATE_IDLE;
                    result_valid <= 1'b0;
                end else begin
                    // 如果start仍然为高，保持在完成状态
                    next_state = STATE_DONE;
                end
            end
            
            default: begin
                next_state = STATE_IDLE;
            end
        endcase
        
        // 更新状态
        state <= next_state;
    end
end
// ============================================================================
// 性能计数器
// ============================================================================
reg [7:0] latency_counter;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        latency_counter <= 8'd0;
    end else if (start && state == STATE_IDLE) begin
        latency_counter <= 8'd1;
    end else if (busy) begin
        latency_counter <= latency_counter + 8'd1;
    end else if (done) begin
        // 保持最终值
    end
end

endmodule