// modular_exponentiation_montgomery.v
`timescale 1ns / 1ps

module modular_exponentiation_montgomery #(
    parameter TOTAL_BITS = 256,
    parameter EXP_BITS = 32  // 指数位宽
)(
    input wire clk,
    input wire reset_n,
    input wire start,
    
    // 输入（普通域）
    input wire [TOTAL_BITS-1:0] base,       // 底数
    input wire [EXP_BITS-1:0] exponent,     // 指数
    
    // 模数及预计算参数
    input wire [TOTAL_BITS-1:0] N,
    input wire [TOTAL_BITS-1:0] N_prime,
    input wire [TOTAL_BITS-1:0] R_mod_N,
    input wire [TOTAL_BITS-1:0] R2_mod_N,
    
    // 输出（普通域）
    output reg [TOTAL_BITS-1:0] result,
    output reg done
);

// 内部信号
reg [3:0] state;
reg [EXP_BITS-1:0] exp_reg;
reg [TOTAL_BITS-1:0] base_mont;     // 蒙哥马利域的底数
reg [TOTAL_BITS-1:0] result_mont;   // 蒙哥马利域的结果

// 蒙哥马利模乘控制信号
reg mont_mult_start;
wire mont_mult_done;
wire [TOTAL_BITS-1:0] mont_mult_result;
reg [TOTAL_BITS-1:0] mont_mult_a, mont_mult_b;

// 域转换器控制信号
reg converter_start;
wire converter_done;
wire [TOTAL_BITS-1:0] converter_result;
reg [TOTAL_BITS-1:0] converter_input;
reg converter_direction;

// 蒙哥马利模乘实例
montgomery_multiplier_256bit multiplier (
    .clk(clk),
    .reset_n(reset_n),
    .start(mont_mult_start),
    .a_mont(mont_mult_a),
    .b_mont(mont_mult_b),
    .N(N),
    .N_prime(N_prime),
    .result_mont(mont_mult_result),
    .done(mont_mult_done)
);
/* 
// 域转换器实例
montgomery_converter converter (
    .clk(clk),
    .reset_n(reset_n),
    .start(converter_start),
    .normal_input(converter_input),
    .N(N),
    .N_prime(N_prime),
    // .R_mod_N(R_mod_N),
    .R2_mod_N(R2_mod_N),
    .direction(converter_direction),
    .converted_output(converter_result),
    .done(converter_done)
);
 */
// 平方乘算法控制逻辑
localparam S_IDLE = 4'd0;
localparam S_CONVERT_BASE = 4'd1;
localparam S_WAIT_CONVERT_BASE = 4'd2;
localparam S_INIT = 4'd3;
localparam S_CHECK_EXP = 4'd4;
localparam S_SQUARE_SETUP = 4'd5;
localparam S_SQUARE_WAIT = 4'd6;
localparam S_CHECK_BIT = 4'd7;
localparam S_MULTIPLY_SETUP = 4'd8;
localparam S_MULTIPLY_WAIT = 4'd9;
localparam S_CONVERT_BACK = 4'd10;
localparam S_WAIT_CONVERT_BACK = 4'd11;
localparam S_DONE = 4'd12;

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        state <= S_IDLE;
        result <= 0;
        done <= 0;
        exp_reg <= 0;
        base_mont <= 0;
        result_mont <= 0;
        mont_mult_start <= 0;
        converter_start <= 0;
        mont_mult_a <= 0;
        mont_mult_b <= 0;
        converter_input <= 0;
        converter_direction <= 0;
    end else begin
        // 默认值
        mont_mult_start <= 0;
        converter_start <= 0;
        
        case (state)
            S_IDLE: begin
                done <= 0;
                if (start) begin
                    exp_reg <= exponent;
                    // 将底数转换到蒙哥马利域
                    converter_input <= base;
                    converter_direction <= 0;  // 0: 普通域 -> 蒙哥马利域
                    converter_start <= 1;
                    state <= S_CONVERT_BASE;
                end
            end
            
            S_CONVERT_BASE: begin
                converter_start <= 0;
                state <= S_WAIT_CONVERT_BASE;
            end
            
            S_WAIT_CONVERT_BASE: begin
                if (converter_done) begin
                    base_mont <= converter_result;
                    state <= S_INIT;
                end
            end
            
            S_INIT: begin
                // 初始化结果为1的蒙哥马利形式 (即R_mod_N)
                result_mont <= R_mod_N;
                state <= S_CHECK_EXP;
            end
            
            S_CHECK_EXP: begin
                if (exp_reg == 0) begin
                    // 指数处理完成，转换结果回普通域
                    converter_input <= result_mont;
                    converter_direction <= 1;  // 1: 蒙哥马利域 -> 普通域
                    converter_start <= 1;
                    state <= S_CONVERT_BACK;
                end else begin
                    // 设置平方操作
                    mont_mult_a <= base_mont;
                    mont_mult_b <= base_mont;
                    mont_mult_start <= 1;
                    state <= S_SQUARE_SETUP;
                end
            end
            
            S_SQUARE_SETUP: begin
                mont_mult_start <= 0;
                state <= S_SQUARE_WAIT;
            end
            
            S_SQUARE_WAIT: begin
                if (mont_mult_done) begin
                    // 平方完成，更新base_mont
                    base_mont <= mont_mult_result;
                    state <= S_CHECK_BIT;
                end
            end
            
            S_CHECK_BIT: begin
                if (exp_reg[0]) begin
                    // 如果当前位为1，还需要乘到结果中
                    mont_mult_a <= result_mont;
                    mont_mult_b <= base_mont;  // 使用平方后的值
                    mont_mult_start <= 1;
                    state <= S_MULTIPLY_SETUP;
                end else begin
                    // 平方后处理下一位
                    exp_reg <= exp_reg >> 1;
                    state <= S_CHECK_EXP;
                end
            end
            
            S_MULTIPLY_SETUP: begin
                mont_mult_start <= 0;
                state <= S_MULTIPLY_WAIT;
            end
            
            S_MULTIPLY_WAIT: begin
                if (mont_mult_done) begin
                    result_mont <= mont_mult_result;  // 更新乘法结果
                    exp_reg <= exp_reg >> 1;
                    state <= S_CHECK_EXP;
                end
            end
            
            S_CONVERT_BACK: begin
                converter_start <= 0;
                state <= S_WAIT_CONVERT_BACK;
            end
            
            S_WAIT_CONVERT_BACK: begin
                if (converter_done) begin
                    result <= converter_result;
                    state <= S_DONE;
                end
            end
            
            S_DONE: begin
                done <= 1;
                if (!start) begin
                    state <= S_IDLE;
                end
            end
            
            default: state <= S_IDLE;
        endcase
    end
end

endmodule