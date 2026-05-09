// montgomery_converter.v
`timescale 1ns / 1ps

module montgomery_converter #(
    parameter TOTAL_BITS = 256
)(
    input wire clk,
    input wire reset_n,
    input wire start,
    
    // 普通域输入
    input wire [TOTAL_BITS-1:0] normal_input,
    
    // 模数及预计算参数
    input wire [TOTAL_BITS-1:0] N,
    input wire [TOTAL_BITS-1:0] N_prime,
    input wire [TOTAL_BITS-1:0] R_mod_N,   // R mod N
    input wire [TOTAL_BITS-1:0] R2_mod_N,  // R^2 mod N
    
    // 转换方向
    input wire direction,  // 0: 普通域 -> 蒙哥马利域, 1: 蒙哥马利域 -> 普通域
    
    // 输出
    output reg [TOTAL_BITS-1:0] converted_output,
    output reg done
);

// 蒙哥马利模乘控制信号
reg mont_mult_start;
wire mont_mult_done;
wire [TOTAL_BITS-1:0] mont_mult_result;
reg [TOTAL_BITS-1:0] a_mont_reg, b_mont_reg;

// 实例化蒙哥马利模乘模块
montgomery_multiplier_256bit multiplier (
    .clk(clk),
    .reset_n(reset_n),
    .start(mont_mult_start),
    .a_mont(a_mont_reg),
    .b_mont(b_mont_reg),
    .N(N),
    .N_prime(N_prime),
    .result_mont(mont_mult_result),
    .done(mont_mult_done)
);

// 控制逻辑
reg [1:0] state;
localparam S_IDLE = 2'd0;
localparam S_CONVERT = 2'd1;
localparam S_DONE = 2'd2;

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        state <= S_IDLE;
        converted_output <= 0;
        done <= 0;
        mont_mult_start <= 0;
        a_mont_reg <= 0;
        b_mont_reg <= 0;
    end else begin
        case (state)
            S_IDLE: begin
                done <= 0;
                mont_mult_start <= 0;
                if (start) begin
                    // 设置乘数
                    if (direction == 0) begin
                        // 普通域 -> 蒙哥马利域: normal_input * R2_mod_N mod N
                        a_mont_reg <= normal_input;
                        b_mont_reg <= R2_mod_N;
                    end else begin
                        // 蒙哥马利域 -> 普通域: normal_input * 1 mod N
                        // 在蒙哥马利域中，1表示为R_mod_N
                        a_mont_reg <= normal_input;
                        b_mont_reg <= R_mod_N;
                    end
                    mont_mult_start <= 1;
                    state <= S_CONVERT;
                end
            end
            
            S_CONVERT: begin
                mont_mult_start <= 0;  // 脉冲信号，只持续一个周期
                if (mont_mult_done) begin
                    converted_output <= mont_mult_result;
                    state <= S_DONE;
                end
            end
            
            S_DONE: begin
                done <= 1;
                state <= S_IDLE;
            end
        endcase
    end
end

endmodule