// ============================================================================
// 文件名: segmented_256bit_full_butterfly.v
// 描述: 基于分段计算的256位完整蝶形运算子核（同时输出两个分支）
// 创新点: 将256位运算拆分为4个64位并行处理，同时计算加法和减法分支
// ============================================================================
module segmented_256bit_full_butterfly #(
    parameter TOTAL_WIDTH = 256,           // 总数据位宽
    parameter SEG_WIDTH = 64,              // 分段位宽
    parameter SEG_COUNT = TOTAL_WIDTH / SEG_WIDTH  // 分段数
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // 控制信号
    input wire start,        // 开始计算
    output reg done,         // 计算完成
    output reg busy,         // 忙碌状态
    
    // 256位数据输入
    input wire [TOTAL_WIDTH-1:0] x0,      // x0 (256位)
    input wire [TOTAL_WIDTH-1:0] x1,      // x1 (256位)
    input wire [TOTAL_WIDTH-1:0] w,       // w (256位)
    input wire [TOTAL_WIDTH-1:0] N_prime,    // -N^(-1) mod R
    input wire [TOTAL_WIDTH-1:0] modulus, // 256位模数
    
    // 256位结果输出（同时输出两个分支）
    output reg [TOTAL_WIDTH-1:0] result_add,  // 加法结果：x0 + x1*w
    output reg [TOTAL_WIDTH-1:0] result_sub,  // 减法结果：x0 - x1*w
    output reg result_valid                   // 结果有效
);

// ============================================================================
// 复用您现有的分段乘法器和累加器逻辑
// ============================================================================
wire [SEG_WIDTH-1:0] x0_seg [0:SEG_COUNT-1];
wire [SEG_WIDTH-1:0] x1_seg [0:SEG_COUNT-1];
wire [SEG_WIDTH-1:0] w_seg [0:SEG_COUNT-1];
wire [2*SEG_WIDTH-1:0] products [0:SEG_COUNT-1][0:SEG_COUNT-1];

// 数据分段
genvar i;
generate
    for (i = 0; i < SEG_COUNT; i = i + 1) begin : gen_segments
        assign x0_seg[i] = x0[i*SEG_WIDTH +: SEG_WIDTH];
        assign x1_seg[i] = x1[i*SEG_WIDTH +: SEG_WIDTH];
        assign w_seg[i] = w[i*SEG_WIDTH +: SEG_WIDTH];
    end
endgenerate

// 分段乘法器阵列
generate
    for (i = 0; i < SEG_COUNT; i = i + 1) begin : gen_i
        for (genvar j = 0; j < SEG_COUNT; j = j + 1) begin : gen_j
            seg_multiplier_64bit u_mult (
                .a(x1_seg[i]),
                .b(w_seg[j]),
                .result(products[i][j])
            );
        end
    end
endgenerate

// ============================================================================
// 乘积累加器（复用您的逻辑）
// ============================================================================
reg [2*TOTAL_WIDTH-1:0] accumulator;
reg [2:0] accum_phase;
reg [2:0] accum_i, accum_j;
reg [8:0] weight_reg;

wire [8:0] weight_calc = (accum_i + accum_j) * SEG_WIDTH[8:0];
// 乘积累加结果（512位，用于后续模约简）
wire [2*TOTAL_WIDTH-1:0] full_product;  // 512位完整乘积

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        accumulator <= 512'd0;
        accum_phase <= 3'd0;
        accum_i <= 3'd0;
        accum_j <= 3'd0;
        weight_reg <= 9'd0;
    end else if (state == STATE_ACCUMULATE) begin
        // 复用您的累加逻辑
        case (accum_phase)
            3'd0: begin
                accumulator <= 512'd0;
                accum_i <= 3'd0;
                accum_j <= 3'd0;
                accum_phase <= 3'd1;
            end
            3'd1: begin
                weight_reg <= weight_calc;
                if (weight_calc <= 511) begin
                    accumulator <= accumulator + (products[accum_i][accum_j] << weight_calc);
                end
                
                if (accum_j < SEG_COUNT-1) begin
                    accum_j <= accum_j + 1;
                end else begin
                    accum_j <= 3'd0;
                    if (accum_i < SEG_COUNT-1) begin
                        accum_i <= accum_i + 1;
                    end else begin
                        accum_phase <= 3'd2;
                    end
                end
            end
            3'd2: begin
                accum_phase <= 3'd3;
            end
            3'd3: begin
                // 保持状态
            end
        endcase
    end else if (state != STATE_ACCUMULATE) begin
        accum_phase <= 3'd0;
        accum_i <= 3'd0;
        accum_j <= 3'd0;
    end
end

assign full_product = accumulator;


// ============================================================================
// 同时计算加法和减法分支
// ============================================================================
wire [TOTAL_WIDTH-1:0] add_result, sub_result;
wire [TOTAL_WIDTH:0] temp_sum = {1'b0, x0} + {1'b0, montgomery_result};

// 加法分支：x0 + x1*w
assign add_result = (temp_sum >= {1'b0, modulus}) ? 
                    (temp_sum - {1'b0, modulus}) : 
                    temp_sum[TOTAL_WIDTH-1:0];

// 减法分支：x0 - x1*w
wire [TOTAL_WIDTH:0] temp_diff_check = {1'b0, x0} >= {1'b0, montgomery_result};
wire [TOTAL_WIDTH-1:0] sub_result_raw = (temp_diff_check) ? 
                                        (x0 - montgomery_result) : 
                                        (x0 + modulus - montgomery_result);

// 确保结果在模数范围内
assign sub_result = (sub_result_raw >= modulus) ? 
                    (sub_result_raw - modulus) : 
                    sub_result_raw;

// ============================================================================
// 状态机（修改为同时输出两个结果）
// ============================================================================
reg [3:0] state;
reg [3:0] next_state;

localparam [3:0]
    STATE_IDLE        = 4'd0,
    STATE_SPLIT       = 4'd1,
    STATE_COMPUTE     = 4'd2,
    STATE_ACCUMULATE  = 4'd3,
    STATE_MOD_REDUCE  = 4'd4,
    STATE_OUTPUT      = 4'd5,   // 同时输出两个结果
    STATE_DONE        = 4'd6;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= STATE_IDLE;
        done <= 1'b0;
        busy <= 1'b0;
        result_add <= {TOTAL_WIDTH{1'b0}};
        result_sub <= {TOTAL_WIDTH{1'b0}};
        result_valid <= 1'b0;
    end else begin
        next_state = state;
        
        case (state)
            STATE_IDLE: begin
                done <= 1'b0;
                busy <= 1'b0;
                result_valid <= 1'b0;
                
                if (start) begin
                    busy <= 1'b1;
                    next_state = STATE_SPLIT;
                end
            end
            
            STATE_SPLIT: begin
                next_state = STATE_COMPUTE;
            end
            
            STATE_COMPUTE: begin
                next_state = STATE_ACCUMULATE;
            end
            
            STATE_ACCUMULATE: begin
                if (accum_phase == 3'd3) begin
                    next_state = STATE_MOD_REDUCE;
                end
            end
            
            STATE_MOD_REDUCE: begin
                if (montgomery_done) begin
                    next_state = STATE_OUTPUT;
                end
            end
            
            STATE_OUTPUT: begin
                // 同时输出两个结果
                result_add <= add_result;
                result_sub <= sub_result;
                next_state = STATE_DONE;
            end
            
            STATE_DONE: begin
                result_valid <= 1'b1;
                done <= 1'b1;
                busy <= 1'b0;
                
                if (!start) begin
                    next_state = STATE_IDLE;
                    result_valid <= 1'b0;
                end
            end
        endcase
        
        state <= next_state;
    end
end
// ============================================================================
// 蒙哥马利约简模块（复用）
// ============================================================================
wire [TOTAL_WIDTH-1:0] montgomery_result;
wire montgomery_done;

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
    .t(full_product),
    .mont_result(montgomery_result),
    .valid_out(montgomery_valid),
    .done(montgomery_done)
);

endmodule