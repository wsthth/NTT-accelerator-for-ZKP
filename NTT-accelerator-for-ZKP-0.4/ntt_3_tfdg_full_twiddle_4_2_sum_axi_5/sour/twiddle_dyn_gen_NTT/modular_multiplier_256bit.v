// modular_multiplier_256bit.v
`timescale 1ns / 1ps

module modular_multiplier_256bit #(
    parameter DATA_WIDTH = 256
)(
    input wire clk,
    input wire reset_n,
    input wire start,
    input wire [DATA_WIDTH-1:0] a,
    input wire [DATA_WIDTH-1:0] b,
    input wire [DATA_WIDTH-1:0] modulus,
    output reg [DATA_WIDTH-1:0] result,
    output reg done
);

// ================= 内部寄存器 =================
reg [2*DATA_WIDTH-1:0] product;  // 512位乘积
reg [DATA_WIDTH-1:0] a_reg, b_reg, modulus_reg;
reg [4:0] count;
reg busy;
reg [2:0] state;

// 使用Barrett约简的常数
localparam [DATA_WIDTH-1:0] MU = 256'h100000000000000000000000000000000;  // 2^(2*DATA_WIDTH) / modulus 的近似值

localparam IDLE    = 3'd0;
localparam MULT    = 3'd1;
localparam REDUCE  = 3'd2;
localparam FINISH  = 3'd3;

// ================= Barrett约简函数 =================
function [DATA_WIDTH-1:0] barrett_reduce;
    input [2*DATA_WIDTH-1:0] value;
    input [DATA_WIDTH-1:0] modulus;
    input [DATA_WIDTH-1:0] mu;
    reg [2*DATA_WIDTH-1:0] q_est;
    reg [2*DATA_WIDTH-1:0] reduced;
    integer i;  // 将 int 改为 integer
begin
    // Barrett约简算法：
    // 1. 计算 q_est = floor(value * mu / 2^{2n})
    // 2. 计算 r = value - q_est * modulus
    // 3. 如果 r >= modulus，则 r = r - modulus
    
    // 注意：这是简化版本，实际需要根据具体模数优化
    q_est = (value * mu) >> (2*DATA_WIDTH);
    reduced = value - q_est * modulus;
    
    // 可能需要多次减法（最多3次）
    for (i = 0; i < 3; i = i + 1) begin
        if (reduced >= modulus) begin
            reduced = reduced - modulus;
        end
    end
    
    barrett_reduce = reduced[DATA_WIDTH-1:0];
end
endfunction

// ================= 主状态机 =================
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        state <= IDLE;
        result <= 0;
        done <= 0;
        count <= 0;
        busy <= 0;
        product <= 0;
        a_reg <= 0;
        b_reg <= 0;
        modulus_reg <= 0;
    end else begin
        done <= 0;
        
        case (state)
            IDLE: begin
                if (start && !busy) begin
                    a_reg <= a;
                    b_reg <= b;
                    modulus_reg <= modulus;
                    product <= 0;
                    count <= 0;
                    busy <= 1;
                    state <= MULT;
                    
                    $display("[%t] ModMult: Starting multiplication", $time);
                    $display("[%t] ModMult: a=%h, b=%h, modulus=%h", $time, a, b, modulus);
                end
            end
            
            MULT: begin
                // 多周期乘法（简化实现）
                // 实际中可能需要更高效的乘法算法
                if (count == 0) begin
                    // 计算乘积
                    product = a_reg * b_reg;
                    count <= count + 1;
                    state <= REDUCE;
                end
            end
            
/*             REDUCE: begin
                if (count == 1) begin
                    // 使用Barrett约简
                    result <= barrett_reduce(product, modulus_reg, MU);
                    count <= count + 1;
                    state <= FINISH;
                end
            end
 */ 
            REDUCE: begin
                if (count == 1) begin
                    // 特殊处理模数为0和1的情况
                    if (modulus_reg == 0) begin
                        // 模数为0，不进行模运算
                        result <= product[DATA_WIDTH-1:0];
                    end else if (modulus_reg == 1) begin
                        // 模数为1，任何数模1等于0
                        result <= 0;
                    end else begin
                        // 使用Barrett约简
                        result <= barrett_reduce(product, modulus_reg, MU);
                    end
                    count <= count + 1;
                    state <= FINISH;
                end
            end
 
            FINISH: begin
                done <= 1;
                busy <= 0;
                state <= IDLE;
                
                $display("[%t] ModMult: Result = %h", $time, result);
            end
            
            default: state <= IDLE;
        endcase
    end
end

endmodule