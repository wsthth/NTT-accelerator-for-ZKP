// ============================================================================
// 文件名: simple_64bit_subcore.v
// 描述: 简化版64位子核，处理64位分段数据
// 输入: 64位分段数据，进行模乘和加减运算
// 输出: 64位结果，供上层拼接为256位
// ============================================================================
module simple_64bit_subcore #(
    parameter DATA_WIDTH = 64,
    parameter MODULUS = 64'hFFFFFFFF00000001  // 默认模数
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // 控制信号
    input wire start,        // 开始计算
    input wire add_mode,     // 0:减法, 1:加法
    output reg done,         // 计算完成
    output reg busy,         // 忙碌状态
    
    // 数据输入
    input wire [DATA_WIDTH-1:0] x0_i,    // x0的第i个64位分段
    input wire [DATA_WIDTH-1:0] x1_i,    // x1的第i个64位分段
    input wire [DATA_WIDTH-1:0] w_i,     // w的第i个64位分段
    input wire [DATA_WIDTH-1:0] modulus, // 模数
    
    // 结果输出
    output reg [DATA_WIDTH-1:0] result,  // 64位结果
    output reg result_valid               // 结果有效
);

// ============================================================================
// 状态机定义
// ============================================================================
localparam [2:0]
    STATE_IDLE   = 3'b000,
    STATE_MUL    = 3'b001,  // 乘法阶段
    STATE_MOD    = 3'b010,  // 模约简阶段
    STATE_ADDSUB = 3'b011,  // 加减法阶段
    STATE_DONE   = 3'b100;
    
reg [2:0] current_state, next_state;

// ============================================================================
// 数据寄存器
// ============================================================================
reg [DATA_WIDTH-1:0] x0_reg, x1_reg, w_reg, mod_reg;
reg [2*DATA_WIDTH-1:0] product;  // 128位乘积
reg [DATA_WIDTH-1:0] product_mod; // 模约简后的乘积
reg [DATA_WIDTH-1:0] final_result; // 最终结果

// ============================================================================
// 计数器
// ============================================================================
reg [3:0] cycle_counter;

// ============================================================================
// 状态机主逻辑
// ============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        current_state <= STATE_IDLE;
        done <= 1'b0;
        busy <= 1'b0;
        result_valid <= 1'b0;
        
        // 复位寄存器
        x0_reg <= {DATA_WIDTH{1'b0}};
        x1_reg <= {DATA_WIDTH{1'b0}};
        w_reg <= {DATA_WIDTH{1'b0}};
        mod_reg <= MODULUS;
        product <= {2*DATA_WIDTH{1'b0}};
        product_mod <= {DATA_WIDTH{1'b0}};
        final_result <= {DATA_WIDTH{1'b0}};
        result <= {DATA_WIDTH{1'b0}};
        cycle_counter <= 4'd0;
    end else begin
        current_state <= next_state;
        
        case (current_state)
            STATE_IDLE: begin
                done <= 1'b0;
                busy <= 1'b0;
                result_valid <= 1'b0;
                cycle_counter <= 4'd0;
                
                if (start) begin
                    // 锁存输入数据
                    x0_reg <= x0_i;
                    x1_reg <= x1_i;
                    w_reg <= w_i;
                    mod_reg <= modulus;
                    busy <= 1'b1;
                    next_state <= STATE_MUL;
                end else begin
                    next_state <= STATE_IDLE;
                end
            end
            
            STATE_MUL: begin
                // 64位乘法: product = x1_i * w_i
                product <= x1_reg * w_reg;
                cycle_counter <= cycle_counter + 1;
                next_state <= STATE_MOD;
            end
            
            STATE_MOD: begin
                // 简单的模约简: product_mod = product % modulus
                // 注意: 实际应用中应该使用蒙哥马利约简
                product_mod <= product % mod_reg;
                cycle_counter <= cycle_counter + 1;
                next_state <= STATE_ADDSUB;
            end
            
            STATE_ADDSUB: begin
                if (add_mode) begin
                    // 加法模式: final_result = (x0_i + product_mod) % modulus
                    final_result <= (x0_reg + product_mod) % mod_reg;
                end else begin
                    // 减法模式: final_result = (x0_i - product_mod + modulus) % modulus
                    if (x0_reg >= product_mod) begin
                        final_result <= (x0_reg - product_mod) % mod_reg;
                    end else begin
                        final_result <= (x0_reg + mod_reg - product_mod) % mod_reg;
                    end
                end
                cycle_counter <= cycle_counter + 1;
                next_state <= STATE_DONE;
            end
            
            STATE_DONE: begin
                // 输出结果
                result <= final_result;
                result_valid <= 1'b1;
                done <= 1'b1;
                busy <= 1'b0;
                
                if (!start) begin
                    next_state <= STATE_IDLE;
                    result_valid <= 1'b0;
                end else begin
                    next_state <= STATE_DONE;
                end
            end
            
            default: begin
                next_state <= STATE_IDLE;
            end
        endcase
    end
end

endmodule

