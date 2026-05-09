// modular_exponentiation.v
`timescale 1ns / 1ps

module modular_exponentiation #(
    parameter DATA_WIDTH = 16
)(
    input wire clk,
    input wire reset_n,
    input wire start,
    input wire [DATA_WIDTH-1:0] base,
    input wire [15:0] exponent,
    input wire [DATA_WIDTH-1:0] modulus,
    output reg [DATA_WIDTH-1:0] result,
    output reg done
);

// ================= 内部寄存器 =================
reg [DATA_WIDTH-1:0] base_reg;
reg [15:0] exp_reg;
reg [DATA_WIDTH-1:0] result_reg;
reg [4:0] bit_idx;      // 5位，支持0-31
reg busy;
reg [3:0] state;        // 扩展为4位，支持更多状态

// 模乘接口
wire [DATA_WIDTH-1:0] mod_mult_result;
wire mod_mult_done;
reg mod_mult_start;
reg [DATA_WIDTH-1:0] mod_mult_a;
reg [DATA_WIDTH-1:0] mod_mult_b;

// 模乘模块实例
modular_multiplier_256bit mod_mult_inst (
    .clk(clk),
    .rst_n(reset_n),
    .start(mod_mult_start),
    .a(mod_mult_a),
    .b(mod_mult_b),
    .N(modulus),
    .Np(),
    .R2_mod_N(),
    .result(mod_mult_result),
    .done(mod_mult_done),
    .busy()
);


 
// ================= 状态定义 =================
localparam IDLE            = 4'd0;
localparam INIT            = 4'd1;
localparam PROCESS         = 4'd2;
localparam PROCESS_SQUARE  = 4'd3;
localparam PROCESS_CHECK   = 4'd4;
localparam PROCESS_MULT    = 4'd5;
localparam FINISH          = 4'd6;

// ================= 简化状态机 =================
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        state <= IDLE;
        result <= 0;
        done <= 0;
        busy <= 0;
        base_reg <= 0;
        exp_reg <= 0;
        result_reg <= 0;
        bit_idx <= 15;  // 从第15位开始（16位指数）
        mod_mult_start <= 0;
    end else begin
        mod_mult_start <= 0;
        done <= 0;
        
        case (state)
            IDLE: begin
                if (start && !busy) begin
                    base_reg <= base;
                    exp_reg <= exponent;
                    result_reg <= 1;  // 初始化为1
                    bit_idx <= 15;    // 重置为15
                    busy <= 1;
                    state <= INIT;
                    
                    $display("[%t] ModExp: Starting, base=%h, exp=%d, modulus=%h", 
                             $time, base, exponent, modulus);
                end
            end
            
            INIT: begin
                // 如果指数为0，直接返回1
                if (exp_reg == 0) begin
                    result_reg <= 1;
                    state <= FINISH;
                    $display("[%t] ModExp: Exponent is 0, result=1", $time);
                end else begin
                    // 找到最高有效位
                    // 注意：这里不能使用while循环，必须使用状态机
                    if (bit_idx > 0 && exp_reg[bit_idx] == 0) begin
                        bit_idx <= bit_idx - 1;
                        state <= INIT;  // 继续寻找
                    end else begin
                        $display("[%t] ModExp: Highest bit found at %d", $time, bit_idx);
                        state <= PROCESS;
                    end
                end
            end
            
            PROCESS: begin
                if (bit_idx >= 0) begin
                    // 平方操作
                    if (result_reg != 1 || bit_idx != 15) begin
                        mod_mult_a <= result_reg;
                        mod_mult_b <= result_reg;
                        mod_mult_start <= 1;
                        state <= PROCESS_SQUARE;
                        $display("[%t] ModExp: Squaring, bit_idx=%d", $time, bit_idx);
                    end else begin
                        // 第一次平方，result_reg=1，跳过
                        $display("[%t] ModExp: First square skipped", $time);
                        state <= PROCESS_CHECK;
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
                // 检查当前位
                if (exp_reg[bit_idx]) begin
                    // 如果当前位为1，需要乘以base_reg
                    $display("[%t] ModExp: Bit %d is 1, multiply by base", $time, bit_idx);
                    mod_mult_a <= result_reg;
                    mod_mult_b <= base_reg;
                    mod_mult_start <= 1;
                    state <= PROCESS_MULT;
                end else begin
                    // 准备处理下一位
                    $display("[%t] ModExp: Bit %d is 0, move to next bit", $time, bit_idx);
                    if (bit_idx == 0) begin
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
                    // 准备处理下一位
                    if (bit_idx == 0) begin
                        state <= FINISH;
                    end else begin
                        bit_idx <= bit_idx - 1;
                        state <= PROCESS;
                    end
                end
            end
            
            FINISH: begin
                result <= result_reg;
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