// modular_exponentiation.v
`timescale 1ns / 1ps

module modular_exponentiation #(
    parameter DATA_WIDTH = 256,
    parameter EXP_WIDTH = 256
)(
    input wire clk,
    input wire reset_n,
    input wire start,
    input wire [DATA_WIDTH-1:0] base,
    input wire [EXP_WIDTH-1:0] exponent,
    input wire [DATA_WIDTH-1:0] modulus,
    input wire [DATA_WIDTH-1:0] Np,        // -N^{-1} mod R (外部提供)
    input wire [DATA_WIDTH-1:0] R2_mod_N,  // R^2 mod N (外部提供)
    output reg [DATA_WIDTH-1:0] result,
    output reg done
);

// ================= 内部寄存器 =================
reg [DATA_WIDTH-1:0] base_reg;
reg [EXP_WIDTH-1:0] exp_reg;
reg [DATA_WIDTH-1:0] result_reg;
reg [7:0] bit_idx;      // 8位，支持0-255位指数
reg busy;
reg [3:0] state;        // 状态寄存器
reg [DATA_WIDTH-1:0] R2_mod_N_reg;
reg [DATA_WIDTH-1:0] Np_reg;

// ================= 模乘接口 =================
wire [DATA_WIDTH-1:0] mod_mult_result;
wire mod_mult_done;
reg mod_mult_start;
reg [DATA_WIDTH-1:0] mod_mult_a;
reg [DATA_WIDTH-1:0] mod_mult_b;

// ================= 模乘模块实例 =================
// 注意：modular_multiplier内部已经处理了域转换
// 输入a和b是普通域的数，输出结果也是普通域的数
modular_multiplier_256bit#(
    .WIDTH(DATA_WIDTH),
    .PIPELINE_STAGES(4)
)mod_mult_inst
(
    .clk(clk),
    .rst_n(reset_n),
    .start(mod_mult_start),
    .a(mod_mult_a),
    .b(mod_mult_b),
    .N(modulus),
    .Np(Np_reg),
    .R2_mod_N(R2_mod_N_reg),
    .result(mod_mult_result),
    .done(mod_mult_done),
    .busy()
);

// ================= 状态定义 =================
localparam IDLE              = 4'd0;
localparam INIT              = 4'd1;
localparam FIND_MSB          = 4'd2;  // 寻找最高有效位
localparam PROCESS           = 4'd3;  // 主处理状态
localparam PROCESS_SQUARE    = 4'd4;  // 执行平方运算
localparam PROCESS_CHECK     = 4'd5;  // 检查指数当前位
localparam PROCESS_MULT      = 4'd6;  // 执行乘法运算
localparam FINISH            = 4'd7;  // 完成

// ================= 状态机 =================
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        state <= IDLE;
        result <= 0;
        done <= 0;
        busy <= 0;
        base_reg <= 0;
        exp_reg <= 0;
        result_reg <= 0;
        bit_idx <= EXP_WIDTH - 1;
        mod_mult_start <= 0;
        R2_mod_N_reg <= 0;
        Np_reg <= 0;
        
        mod_mult_a <=0;
        mod_mult_b <=0;
    end else begin
        mod_mult_start <= 0;
        done <= 0;
        
        case (state)
            IDLE: begin
                if (start && !busy) begin
                    // 检查模数是否为奇数（蒙哥马利算法要求）
                    if (modulus == 0 || modulus[0] == 0) begin
                        $display("[%t] ModExp: Error - modulus must be odd for Montgomery multiplication", $time);
                        result <= 0;
                        done <= 1;
                        state <= IDLE;
                    end else begin
                        // 寄存输入参数
                        base_reg <= base;
                        exp_reg <= exponent;
                        result_reg <= 1;  // 初始结果为1（普通域）
                        R2_mod_N_reg <= R2_mod_N;
                        Np_reg <= Np;
                        
                        // 初始化bit_idx
                        if (exponent == 0) begin
                            // 指数为0，直接返回1
                            bit_idx <= 0;
                            state <= FINISH;
                        end else begin
                            bit_idx <= EXP_WIDTH - 1;
                            state <= FIND_MSB;
                        end
                        
                        busy <= 1;
                        $display("[%t] ModExp: Starting, base=%h, exp=%h, modulus=%h", 
                                 $time, base, exponent, modulus);
                    end
                end
            end
            
            FIND_MSB: begin
                // 寻找最高有效位（从高位向低位搜索）
                if (bit_idx > 0 && exp_reg[bit_idx] == 0) begin
                    bit_idx <= bit_idx - 1;
                    // 继续寻找
                end else begin
                    // 找到最高有效位
                    $display("[%t] ModExp: Highest bit found at %d", $time, bit_idx);
                    state <= PROCESS;
                end
            end
            
            PROCESS: begin
                if (bit_idx >= 0) begin
                    // 检查是否需要执行平方操作
                    // 第一次迭代时，result_reg=1，平方操作可以跳过
                    if (result_reg == 1 && bit_idx == EXP_WIDTH-1) begin
                        // 第一次迭代且结果为1，跳过平方
                        $display("[%t] ModExp: First iteration, skipping square", $time);
                        state <= PROCESS_CHECK;
                    end else begin
                        // 执行平方操作
                        mod_mult_a <= result_reg;
                        mod_mult_b <= result_reg;
                        mod_mult_start <= 1;
                        state <= PROCESS_SQUARE;
                        $display("[%t] ModExp: Squaring, bit_idx=%d, result_reg=%h", 
                                 $time, bit_idx, result_reg);
                    end
                end else begin
                    // 所有位处理完毕
                    state <= FINISH;
                    $display("[%t] ModExp: All bits processed", $time);
                end
            end
            
            PROCESS_SQUARE: begin
                if (mod_mult_done) begin
                    result_reg <= mod_mult_result;
                    $display("[%t] ModExp: Square done, result=%h", $time, mod_mult_result);
                    state <= PROCESS_CHECK;
                end
            end
            
            PROCESS_CHECK: begin
                // 检查指数当前位
                if (exp_reg[bit_idx]) begin
                    // 当前位为1，需要乘以base_reg
                    $display("[%t] ModExp: Bit %d is 1, multiply by base=%h", 
                             $time, bit_idx, base_reg);
                    mod_mult_a <= result_reg;
                    mod_mult_b <= base_reg;
                    mod_mult_start <= 1;
                    state <= PROCESS_MULT;
                end else begin
                    // 当前位为0，处理下一位
                    $display("[%t] ModExp: Bit %d is 0, move to next bit", $time, bit_idx);
                    if (bit_idx == 0) begin
                        // 最后一位处理完毕
                        state <= FINISH;
                    end else begin
                        bit_idx <= bit_idx - 1;
                        state <= PROCESS;
                    end
                end
            end
            
            PROCESS_MULT: begin
                if (mod_mult_done) begin
                    result_reg <= mod_mult_result;
                    $display("[%t] ModExp: Multiply done, result=%h", $time, mod_mult_result);
                    
                    // 处理下一位
                    if (bit_idx == 0) begin
                        // 最后一位处理完毕
                        state <= FINISH;
                    end else begin
                        bit_idx <= bit_idx - 1;
                        state <= PROCESS;
                    end
                end
            end
            
            FINISH: begin
                result <= result_reg;  // 最终结果（已经在普通域）
                done <= 1;
                busy <= 0;
                state <= IDLE;
                $display("[%t] ModExp: Finished, result=%h", $time, result_reg);
            end
            
            default: state <= IDLE;
        endcase
    end
end

endmodule