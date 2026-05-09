// ============================================================================
// 文件名: reconfigurable_winograd_butterfly.v
// 描述: 统一的蝶形运算引擎 - 真正实现硬件共享
// ============================================================================
module reconfigurable_winograd_butterfly #(
/*     parameter DATA_WIDTH = 256,
    parameter MAX_RADIX = 16,
    parameter MULT_ARRAY_SIZE = 8,  // 乘法器阵列大小
    parameter PIPELINE_STAGES = 4,  // 乘法器流水线深度
    parameter EXP_WIDTH = 8         // 指数位宽
 */    
    parameter DATA_WIDTH = 128,
    parameter MAX_RADIX = 4,
    parameter MULT_ARRAY_SIZE = 4,  // 乘法器阵列大小
    parameter PIPELINE_STAGES = 4,  // 乘法器流水线深度
    parameter EXP_WIDTH = 8         // 指数位宽
    
    
    
)(
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [3:0] radix_cfg,      // 基数配置: 2/4/8/16 (必须是2的幂次)
    input wire [1:0] width_cfg,      // 位宽配置
    
    // 输入数据端口
    input wire [DATA_WIDTH-1:0] x_in [0:MAX_RADIX-1],
    input wire [DATA_WIDTH-1:0] twiddle_base,     // 基础旋转因子 ω
    input wire [DATA_WIDTH-1:0] modulus,
    input wire [DATA_WIDTH-1:0] N_prime,
    input wire [DATA_WIDTH-1:0] R2_mod_N,  // R^2 mod N (用于模幂运算)
    
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

// 模幂运算相关信号
wire [DATA_WIDTH-1:0] twiddle_power_result;
wire twiddle_power_done;
reg twiddle_power_start;
reg [DATA_WIDTH-1:0] twiddle_power_base;
reg [EXP_WIDTH-1:0] twiddle_power_exp;

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

// WNTT系数
reg [DATA_WIDTH-1:0] wntt_coeff [0:MAX_RADIX-1][0:MAX_RADIX-1];
reg coeff_ready;

// 掩码计算：对于2的幂次N，取模N等价于 & (N-1)
wire [3:0] radix_mask = radix_cfg - 1'b1;

localparam [3:0]
    STATE_IDLE        = 4'd0,
    STATE_INIT        = 4'd1,
    STATE_CALC_COEFF  = 4'd2,  // 新增：计算系数状态
    STATE_LOAD        = 4'd3,
    STATE_MULT        = 4'd4,
    STATE_ACCUM       = 4'd5,
    STATE_WAIT        = 4'd6,
    STATE_OUTPUT      = 4'd7;

// ============================================================================
// 模幂运算模块实例化
// ============================================================================
modular_exponentiation #(
    .DATA_WIDTH(DATA_WIDTH),
    .EXP_WIDTH(EXP_WIDTH)
) u_mod_exp (
    .clk(clk),
    .reset_n(rst_n),
    .start(twiddle_power_start),
    .base(twiddle_power_base),
    .exponent(twiddle_power_exp),
    .modulus(modulus),
    .Np(N_prime),
    .R2_mod_N(R2_mod_N),
    .result(twiddle_power_result),
    .done(twiddle_power_done)
);

// ============================================================================
// 分段乘法器阵列实例化
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
            .add_mode(1'b0),
            .done(mult_done[i]),
            .busy(),
            .x0(multiplicand_array[i]),
            .x1(multiplier_array[i]),
            .w(multiplier_array[i]),
            .N_prime(N_prime),
            .modulus(modulus),
            .result(product_array[i]),
            .result_valid(mult_valid[i])
        );
    end
endgenerate

// ============================================================================
// 辅助函数：计算 j * k mod radix (使用位运算优化)
// ============================================================================
function [EXP_WIDTH-1:0] mod_radix_mult;
    input [3:0] j;
    input [3:0] k;
    input [3:0] radix;
    reg [7:0] product;
    begin
        product = j * k;
        // 对于2的幂次，取模等价于与掩码相与
        case (radix)
            4'd2:  mod_radix_mult = product[0];        // 取最低位
            4'd4:  mod_radix_mult = product[1:0];      // 取低2位
            4'd8:  mod_radix_mult = product[2:0];      // 取低3位
            4'd16: mod_radix_mult = product[3:0];      // 取低4位
            default: mod_radix_mult = product[3:0];    // 默认取低4位
        endcase
    end
endfunction

// ============================================================================
// 动态配置累加器索引
// ============================================================================
integer i;
always @(*) begin
    case (radix_cfg)
        4'd2: begin
            for (i = 0; i < MULT_ARRAY_SIZE; i = i + 1) begin
                if (i < 2) begin
                    accum_idx[i] = (i == 0) ? 2'h0 : 2'h1;
                end else begin
                    accum_idx[i] = 4'hF;
                end
            end
        end
        4'd4: begin
            for (i = 0; i < MULT_ARRAY_SIZE; i = i + 1) begin
                if (i < 16) begin
                    accum_idx[i] = i & 2'b11;  // 改为位运算: i % 4 等价于 i & 3
                end else begin
                    accum_idx[i] = 4'hF;
                end
            end
        end
        default: begin
            for (i = 0; i < MULT_ARRAY_SIZE; i = i + 1) begin
                accum_idx[i] = 4'hF;
            end
        end
    endcase
end

// ============================================================================
// 主状态机
// ============================================================================
integer idx, k_idx;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= STATE_IDLE;
        done <= 1'b0;
        valid <= 1'b0;
        j_counter <= 0;
        k_counter <= 0;
        cycle_counter <= 0;
        coeff_ready <= 1'b0;
        twiddle_power_start <= 1'b0;
        
        for (idx = 0; idx < MAX_RADIX; idx = idx + 1)
            accumulator[idx] <= 0;
            
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
                coeff_ready <= 1'b0;
                
                if (start) begin
                    next_state <= STATE_INIT;
                end else begin
                    next_state <= STATE_IDLE;
                end
            end
            
            STATE_INIT: begin
                for (idx = 0; idx < MAX_RADIX; idx = idx + 1)
                    accumulator[idx] <= 0;
                
                coeff_ready <= 1'b0;
                next_state <= STATE_CALC_COEFF;
            end
            
            STATE_CALC_COEFF: begin
                // 计算WNTT系数矩阵
                if (!coeff_ready) begin
                    if (j_counter < MAX_RADIX && k_counter < MAX_RADIX) begin
                        if (!twiddle_power_start && !twiddle_power_done) begin
                            // 启动模幂运算计算 ω^((j*k) mod radix_cfg)
                            // 使用优化的取模运算
                            twiddle_power_base <= twiddle_base;
                            twiddle_power_exp <= mod_radix_mult(j_counter, k_counter, radix_cfg);
                            twiddle_power_start <= 1'b1;
                        end else if (twiddle_power_done) begin
                            // 模幂运算完成，存储结果
                            wntt_coeff[k_counter][j_counter] <= twiddle_power_result;
                            twiddle_power_start <= 1'b0;
                            
                            // 更新索引
                            if (j_counter < MAX_RADIX - 1) begin
                                j_counter <= j_counter + 1;
                            end else begin
                                j_counter <= 0;
                                if (k_counter < MAX_RADIX - 1) begin
                                    k_counter <= k_counter + 1;
                                end else begin
                                    k_counter <= 0;
                                    coeff_ready <= 1'b1;
                                end
                            end
                        end
                    end
                end
                
                if (coeff_ready) begin
                    next_state <= STATE_LOAD;
                end else begin
                    next_state <= STATE_CALC_COEFF;
                end
            end
            
            STATE_LOAD: begin
                case (radix_cfg)
                    4'd2: begin
                        if (j_counter < 2) begin
                            multiplier_array[0] <= x_in[0];
                            multiplicand_array[0] <= wntt_coeff[0][j_counter];
                            multiplier_array[1] <= x_in[1];
                            multiplicand_array[1] <= wntt_coeff[1][j_counter];
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
                        if (j_counter < 4) begin
                            for (k_idx = 0; k_idx < 4; k_idx = k_idx + 1) begin
                                if (k_idx < MULT_ARRAY_SIZE) begin
                                    multiplier_array[k_idx] <= x_in[j_counter];
                                    multiplicand_array[k_idx] <= wntt_coeff[k_idx][j_counter];
                                end
                            end
                            mult_start <= 4'b1111;
                            j_counter <= j_counter + 1;
                            next_state <= STATE_MULT;
                        end else begin
                            mult_start <= 4'b0000;
                            j_counter <= 0;
                            next_state <= STATE_WAIT;
                        end
                    end
                    
                    default: begin
                        next_state <= STATE_IDLE;
                    end
                endcase
            end
            
            STATE_MULT: begin
                mult_start <= {MULT_ARRAY_SIZE{1'b0}};
                // 等待乘法器完成（简化：固定延迟）
                // 实际应该使用mult_done信号
                if (cycle_counter > 10) begin
                    next_state <= STATE_ACCUM;
                    cycle_counter <= 0;
                end else begin
                    next_state <= STATE_MULT;
                end
            end
            
            STATE_ACCUM: begin
                for (idx = 0; idx < MULT_ARRAY_SIZE; idx = idx + 1) begin
                    if (mult_valid[idx] && accum_idx[idx] != 4'hF) begin
                        accumulator[accum_idx[idx]] <= accumulator[accum_idx[idx]] + product_array[idx];
                    end
                end
                next_state <= STATE_LOAD;
            end
            
            STATE_WAIT: begin
                if (cycle_counter > 5) begin
                    next_state <= STATE_OUTPUT;
                end else begin
                    next_state <= STATE_WAIT;
                end
            end
            
            STATE_OUTPUT: begin
                case (radix_cfg)
                    4'd2: begin
                        x_out[0] <= accumulator[0];
                        x_out[1] <= accumulator[1];
                    end
                    4'd4: begin
                        for (idx = 0; idx < 4; idx = idx + 1)
                            x_out[idx] <= accumulator[idx];
                    end
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