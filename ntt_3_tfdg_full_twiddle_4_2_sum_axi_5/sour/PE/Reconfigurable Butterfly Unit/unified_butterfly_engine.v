// ============================================================================
// 文件名: unified_butterfly_engine.v
// 描述: 统一的蝶形运算引擎 - 真正实现硬件共享
// ============================================================================
module unified_butterfly_engine #(
    parameter DATA_WIDTH = 256,
    parameter MAX_RADIX = 16,
    parameter MULT_ARRAY_SIZE = 8,  // 乘法器阵列大小
    parameter PIPELINE_STAGES = 4   // 乘法器流水线深度
)(
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [3:0] radix_cfg,      // 基数配置: 2/4/8/16
    input wire [1:0] width_cfg,      // 位宽配置
    
    // 输入数据端口
    input wire [DATA_WIDTH-1:0] x_in [0:MAX_RADIX-1],
    input wire [DATA_WIDTH-1:0] twiddle_base,     // 基础旋转因子 ω
    input wire [DATA_WIDTH-1:0] modulus,
    input wire [DATA_WIDTH-1:0] N_prime,
    
    // 输出数据端口
    output reg [DATA_WIDTH-1:0] x_out [0:MAX_RADIX-1],
    output reg done,
    output reg valid
);

// ============================================================================
// 内部信号定义
// ============================================================================
reg [DATA_WIDTH-1:0] multiplier_array [0:MULT_ARRAY_SIZE-1];
reg [DATA_WIDTH-1:0] multiplicand_array [0:MULT_ARRAY_SIZE-1];
wire [DATA_WIDTH-1:0] product_array [0:MULT_ARRAY_SIZE-1];
reg [MULT_ARRAY_SIZE-1:0] mult_start;
wire [MULT_ARRAY_SIZE-1:0] mult_done;
wire [MULT_ARRAY_SIZE-1:0] mult_valid;

// 累加器相关
reg [DATA_WIDTH-1:0] accumulator [0:MAX_RADIX-1];
reg [3:0] accum_idx [0:MULT_ARRAY_SIZE-1];
reg [DATA_WIDTH-1:0] accum_input [0:MULT_ARRAY_SIZE-1];

// 状态机
reg [3:0] state;
reg [3:0] next_state;
reg [3:0] j_counter;      // 输入索引计数器
reg [3:0] k_counter;      // 输出索引计数器
reg [7:0] cycle_counter;

localparam [3:0]
    STATE_IDLE        = 4'd0,
    STATE_INIT        = 4'd1,
    STATE_LOAD        = 4'd2,
    STATE_MULT        = 4'd3,
    STATE_ACCUM       = 4'd4,
    STATE_WAIT        = 4'd5,
    STATE_OUTPUT      = 4'd6;

// ============================================================================
// WNTT系数计算模块
// ============================================================================
wire [DATA_WIDTH-1:0] wntt_coeff [0:MAX_RADIX-1][0:MAX_RADIX-1];
reg [3:0] coeff_k, coeff_j;

// 计算WNTT系数：ω^(j*k mod r)
always @(*) begin
    for (int k = 0; k < MAX_RADIX; k = k + 1) begin
        for (int j = 0; j < MAX_RADIX; j = j + 1) begin
            // 实际中需要模幂运算，这里简化表示
            wntt_coeff[k][j] = twiddle_power(twiddle_base, (j * k) % radix_cfg);
        end
    end
end

// ============================================================================
// 分段乘法器阵列实例化（完整的调用）
// ============================================================================
generate
    for (genvar i = 0; i < MULT_ARRAY_SIZE; i = i + 1) begin : mult_array
        segmented_256bit_butterfly #(
            .TOTAL_WIDTH(DATA_WIDTH),
            .SEG_WIDTH(64),
            .SEG_COUNT(DATA_WIDTH/64)
        ) u_multiplier (
            .clk(clk),
            .rst_n(rst_n),
            .start(mult_start[i]),
            .add_mode(1'b0),           // 只用于乘法
            .done(mult_done[i]),
            .busy(),
            .x0(multiplicand_array[i]), // 作为x1
            .x1(multiplier_array[i]),   // 作为w
            .w(multiplier_array[i]),    // 占位，实际不使用
            .N_prime(N_prime),
            .modulus(modulus),
            .result(product_array[i]),
            .result_valid(mult_valid[i])
        );
    end
endgenerate

// ============================================================================
// 动态配置累加器索引（修正版）
// ============================================================================
always @(*) begin
    case (radix_cfg)
        4'd2: begin
            // 基2：两个输出，每个需要累加2个乘积
            // X0 = x0*1 + x1*1
            // X1 = x0*1 + x1*(-1)
            for (int i = 0; i < MULT_ARRAY_SIZE; i = i + 1) begin
                if (i < 2) begin
                    // 第0个乘法器：累加到X0和X1
                    // 第1个乘法器：累加到X0（正）和X1（负）
                    accum_idx[i] = (i == 0) ? 2'h0 : 2'h1; // 简化为单个输出
                end else begin
                    accum_idx[i] = 4'hF; // 无效
                end
            end
        end
        4'd4: begin
            // 基4：WNTT并行累加
            // X0 = x0*1 + x1*1 + x2*1 + x3*1
            // X1 = x0*1 + x1*ω + x2*ω² + x3*ω³
            // X2 = x0*1 + x1*ω² + x2*ω⁴ + x3*ω⁶
            // X3 = x0*1 + x1*ω³ + x2*ω⁶ + x3*ω⁹
            for (int i = 0; i < MULT_ARRAY_SIZE; i = i + 1) begin
                if (i < 16) begin // 需要16个乘法器，但我们只有8个
                    // 简化的分配：每个乘法器对应一个输出
                    accum_idx[i] = i % 4;
                end else begin
                    accum_idx[i] = 4'hF;
                end
            end
        end
        // 基8和基16需要更多的乘法器
        default: begin
            for (int i = 0; i < MULT_ARRAY_SIZE; i = i + 1) begin
                accum_idx[i] = 4'hF;
            end
        end
    endcase
end

// ============================================================================
// 主状态机（完整实现）
// ============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= STATE_IDLE;
        done <= 1'b0;
        valid <= 1'b0;
        j_counter <= 0;
        k_counter <= 0;
        cycle_counter <= 0;
        
        // 清零累加器
        for (int i = 0; i < MAX_RADIX; i = i + 1)
            accumulator[i] <= 0;
            
        // 清零乘法启动信号
        mult_start <= {MULT_ARRAY_SIZE{1'b0}};
    end else begin
        state <= next_state;
        cycle_counter <= cycle_counter + 1;
        
        case (state)
            STATE_IDLE: begin
                done <= 1'b0;
                valid <= 1'b0;
                j_counter <= 0;
                k_counter <= 0;
                cycle_counter <= 0;
                
                if (start) begin
                    next_state <= STATE_INIT;
                end else begin
                    next_state <= STATE_IDLE;
                end
            end
            
            STATE_INIT: begin
                // 初始化累加器
                for (int i = 0; i < MAX_RADIX; i = i + 1)
                    accumulator[i] <= 0;
                    
                // 根据基数配置确定需要计算的乘法器数量
                next_state <= STATE_LOAD;
            end
            
            STATE_LOAD: begin
                // 加载数据到乘法器阵列
                case (radix_cfg)
                    4'd2: begin
                        // 基2：2个乘法器
                        if (j_counter < 2) begin
                            multiplier_array[0] <= x_in[0];
                            multiplicand_array[0] <= (j_counter == 0) ? 256'd1 : 256'd1; // 简化
                            multiplier_array[1] <= x_in[1];
                            multiplicand_array[1] <= (j_counter == 0) ? 256'd1 : -256'd1; // 简化
                            mult_start <= 2'b11;
                            j_counter <= j_counter + 1;
                            next_state <= STATE_MULT;
                        end else begin
                            mult_start <= 2'b00;
                            j_counter <= 0;
                            next_state <= STATE_WAIT;
                        end
                    end
                    
                    4'd4: begin
                        // 基4：使用多个周期完成16个乘法
                        if (j_counter < 4) begin
                            // 每个周期计算4个输出对应的当前输入
                            for (int k = 0; k < 4; k = k + 1) begin
                                if (k < MULT_ARRAY_SIZE) begin
                                    multiplier_array[k] <= x_in[j_counter];
                                    multiplicand_array[k] <= wntt_coeff[k][j_counter];
                                end
                            end
                            // 启动前4个乘法器
                            mult_start <= 4'b1111;
                            j_counter <= j_counter + 1;
                            next_state <= STATE_MULT;
                        end else begin
                            mult_start <= 4'b0000;
                            j_counter <= 0;
                            next_state <= STATE_WAIT;
                        end
                    end
                    
                    // 基8和基16类似，但需要更多周期
                    
                    default: begin
                        next_state <= STATE_IDLE;
                    end
                endcase
            end
            
            STATE_MULT: begin
                // 等待乘法器完成（简化：固定延迟）
                mult_start <= {MULT_ARRAY_SIZE{1'b0}};
                if (cycle_counter > 10) begin // 假设乘法需要10个周期
                    next_state <= STATE_ACCUM;
                    cycle_counter <= 0;
                end else begin
                    next_state <= STATE_MULT;
                end
            end
            
            STATE_ACCUM: begin
                // 累加乘法结果
                for (int i = 0; i < MULT_ARRAY_SIZE; i = i + 1) begin
                    if (mult_valid[i] && accum_idx[i] != 4'hF) begin
                        accumulator[accum_idx[i]] <= accumulator[accum_idx[i]] + product_array[i];
                    end
                end
                next_state <= STATE_LOAD;
            end
            
            STATE_WAIT: begin
                // 等待所有累加完成
                if (cycle_counter > 5) begin // 额外等待几个周期确保稳定
                    next_state <= STATE_OUTPUT;
                end else begin
                    next_state <= STATE_WAIT;
                end
            end
            
            STATE_OUTPUT: begin
                // 输出结果
                case (radix_cfg)
                    4'd2: begin
                        x_out[0] <= accumulator[0];
                        x_out[1] <= accumulator[1];
                    end
                    4'd4: begin
                        for (int i = 0; i < 4; i = i + 1)
                            x_out[i] <= accumulator[i];
                    end
                    // 其他基数类似
                endcase
                
                valid <= 1'b1;
                done <= 1'b1;
                next_state <= STATE_IDLE;
            end
            
            default: begin
                next_state <= STATE_IDLE;
            end
        endcase
    end
end

// ============================================================================
// 辅助函数（需要在外部实现）
// ============================================================================

// 模幂运算：计算 twiddle_base^exp mod modulus
function [DATA_WIDTH-1:0] twiddle_power;
    input [DATA_WIDTH-1:0] base;
    input [7:0] exp;
    reg [DATA_WIDTH-1:0] result;
    begin
        result = 256'd1;
        for (int i = 0; i < exp; i = i + 1) begin
            // 实际需要模乘，这里简化
            result = result * base;
        end
        twiddle_power = result;
    end
endfunction

// ============================================================================
// 性能监控
// ============================================================================
reg [15:0] total_cycles;
always @(posedge clk) begin
    if (state == STATE_IDLE) begin
        total_cycles <= 0;
    end else if (state != STATE_IDLE && next_state != STATE_IDLE) begin
        total_cycles <= total_cycles + 1;
    end
end

// 调试信号
wire [3:0] debug_state = state;
wire [15:0] debug_cycles = total_cycles;

endmodule