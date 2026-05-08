// modular_exponentiation_256bit.v
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
    output reg [DATA_WIDTH-1:0] result,
    output reg done
);

// ================= 内部寄存器 =================
reg [DATA_WIDTH-1:0] base_reg;
reg [EXP_WIDTH-1:0] exp_reg;
reg [DATA_WIDTH-1:0] result_reg;
reg [7:0] bit_idx;      // 8位，支持0-255位指数（EXP_WIDTH最大256位）
reg busy;
reg [3:0] state;        // 状态寄存器

// 模乘接口
wire [DATA_WIDTH-1:0] mod_mult_result;
wire mod_mult_done;
reg mod_mult_start;
reg [DATA_WIDTH-1:0] mod_mult_a;
reg [DATA_WIDTH-1:0] mod_mult_b;

// 蒙哥马利参数计算（预计算）
wire [DATA_WIDTH-1:0] Np;        // -N^{-1} mod R
wire [DATA_WIDTH-1:0] R2_mod_N;  // R^2 mod N
reg [DATA_WIDTH-1:0] R2_mod_N_reg; // 缓存R2_mod_N

// 蒙哥马利参数预计算状态
reg calc_params_start;
wire calc_params_done;
reg [1:0] param_state;

// 蒙哥马利参数预计算模块
montgomery_params_calculator #(
    .WIDTH(DATA_WIDTH)
) params_calc_inst (
    .clk(clk),
    .rst_n(reset_n),
    .start(calc_params_start),
    .N(modulus),
    .Np(Np),
    .R2_mod_N(R2_mod_N),
    .done(calc_params_done),
    .busy()
);

// 模乘模块实例（修改为支持DATA_WIDTH位宽）
modular_multiplier #(
    .WIDTH(DATA_WIDTH)
) mod_mult_inst (
    .clk(clk),
    .rst_n(reset_n),
    .start(mod_mult_start),
    .a(mod_mult_a),
    .b(mod_mult_b),
    .N(modulus),
    .Np(Np),
    .R2_mod_N(R2_mod_N_reg),
    .result(mod_mult_result),
    .done(mod_mult_done),
    .busy()
);

// ================= 状态定义 =================
localparam IDLE              = 4'd0;
localparam CALC_PARAMS       = 4'd1;
localparam INIT              = 4'd2;
localparam PROCESS           = 4'd3;
localparam PROCESS_SQUARE    = 4'd4;
localparam PROCESS_CHECK     = 4'd5;
localparam PROCESS_MULT      = 4'd6;
localparam FINISH            = 4'd7;

localparam PARAM_IDLE        = 2'd0;
localparam PARAM_CALCULATING = 2'd1;
localparam PARAM_DONE        = 2'd2;

// ================= 状态机 =================
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        state <= IDLE;
        param_state <= PARAM_IDLE;
        result <= 0;
        done <= 0;
        busy <= 0;
        base_reg <= 0;
        exp_reg <= 0;
        result_reg <= 0;
        bit_idx <= EXP_WIDTH - 1;  // 从最高位开始
        mod_mult_start <= 0;
        calc_params_start <= 0;
        R2_mod_N_reg <= 0;
        
        $display("[%t] ModExp: Reset", $time);
    end else begin
        mod_mult_start <= 0;
        calc_params_start <= 0;
        done <= 0;
        
        case (state)
            IDLE: begin
                if (start && !busy) begin
                    // 检查模数是否为0或1
                    if (modulus == 0 || modulus == 1) begin
                        $display("[%t] ModExp: Error - modulus is 0 or 1", $time);
                        result <= 0;
                        done <= 1;
                        state <= IDLE;
                    end else begin
                        base_reg <= base;
                        exp_reg <= exponent;
                        result_reg <= 1;  // 初始化为1
                        bit_idx <= EXP_WIDTH - 1;  // 重置为最高位
                        busy <= 1;
                        
                        // 开始计算蒙哥马利参数
                        calc_params_start <= 1;
                        param_state <= PARAM_CALCULATING;
                        state <= CALC_PARAMS;
                        
                        $display("[%t] ModExp: Starting, base=%h, exp=%h, modulus=%h", 
                                 $time, base, exponent, modulus);
                    end
                end
            end
            
            CALC_PARAMS: begin
                case (param_state)
                    PARAM_CALCULATING: begin
                        if (calc_params_done) begin
                            R2_mod_N_reg <= R2_mod_N;  // 缓存R2_mod_N
                            param_state <= PARAM_DONE;
                            state <= INIT;
                            
                            $display("[%t] ModExp: Montgomery params calculated", $time);
                            $display("[%t] ModExp: Np=%h, R2_mod_N=%h", $time, Np, R2_mod_N);
                        end
                    end
                    
                    PARAM_DONE: begin
                        // 参数计算完成，进入INIT状态
                        state <= INIT;
                    end
                    
                    default: param_state <= PARAM_IDLE;
                endcase
            end
            
            INIT: begin
                // 如果指数为0，直接返回1
                if (exp_reg == 0) begin
                    result_reg <= 1;
                    state <= FINISH;
                    $display("[%t] ModExp: Exponent is 0, result=1", $time);
                end else begin
                    // 找到最高有效位
                    // 使用状态机方式寻找最高有效位
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
                    if (result_reg != 1 || bit_idx != EXP_WIDTH-1) begin
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
                // 将结果从蒙哥马利域转换回普通域
                // 转换方法: result_reg * 1 mod N
                mod_mult_a <= result_reg;
                mod_mult_b <= 1;  // 转换因子
                mod_mult_start <= 1;
                state <= FINISH_CONV;
                
                $display("[%t] ModExp: Final conversion started", $time);
            end
            
            FINISH_CONV: begin
                if (mod_mult_done) begin
                    result <= mod_mult_result;  // 最终结果
                    done <= 1;
                    busy <= 0;
                    state <= IDLE;
                    
                    $display("[%t] ModExp: Finished, result=%h", $time, mod_mult_result);
                end
            end
            
            default: state <= IDLE;
        endcase
    end
end

endmodule

// ================= 蒙哥马利参数计算模块 =================
module montgomery_params_calculator #(
    parameter WIDTH = 256
)(
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [WIDTH-1:0] N,
    output reg [WIDTH-1:0] Np,
    output reg [WIDTH-1:0] R2_mod_N,
    output reg done,
    output reg busy
);

// R = 2^WIDTH
localparam [WIDTH-1:0] R = {1'b1, {WIDTH-1{1'b0}}};

reg [3:0] state;
reg [WIDTH-1:0] r_mod_n_temp;
reg [2*WIDTH:0] temp;
reg [7:0] count;

localparam IDLE         = 4'd0;
localparam CALC_NP      = 4'd1;
localparam CALC_R2      = 4'd2;
localparam DONE         = 4'd3;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
        Np <= 0;
        R2_mod_N <= 0;
        done <= 0;
        busy <= 0;
        r_mod_n_temp <= 0;
        temp <= 0;
        count <= 0;
    end else begin
        case (state)
            IDLE: begin
                if (start) begin
                    busy <= 1;
                    done <= 0;
                    state <= CALC_NP;
                    count <= 0;
                    
                    // 计算Np = -N^{-1} mod R
                    // 使用扩展欧几里得算法计算模逆
                    $display("[%t] MontgomeryParams: Starting calculation for N=%h", $time, N);
                end
            end
            
            CALC_NP: begin
                // 简化的模逆计算（实际中可能需要更复杂的算法）
                // 这里使用扩展二进制GCD算法
                if (count < WIDTH) begin
                    // 迭代计算Np
                    if (count == 0) begin
                        Np <= 1;  // 初始值
                        temp <= {1'b0, N};
                    end else begin
                        // 简化计算：实际需要完整实现模逆算法
                        if (temp[0]) begin
                            Np <= Np + (1'b1 << count);
                        end
                        temp <= temp >> 1;
                    end
                    count <= count + 1;
                end else begin
                    // 完成Np计算，开始计算R2_mod_N
                    state <= CALC_R2;
                    count <= 0;
                    r_mod_n_temp <= R % N;  // R mod N
                    
                    $display("[%t] MontgomeryParams: Np calculated = %h", $time, Np);
                end
            end
            
            CALC_R2: begin
                // 计算R2_mod_N = (R^2) mod N
                // 使用模幂计算：R^2 mod N
                if (count < 2) begin  // 简化：实际需要完整模幂计算
                    // 这里简化计算，实际需要完整的模幂模块
                    if (count == 0) begin
                        R2_mod_N <= r_mod_n_temp;
                    end else begin
                        // R^2 mod N = (R mod N) * (R mod N) mod N
                        // 简化处理
                        R2_mod_N <= (r_mod_n_temp * r_mod_n_temp) % N;
                    end
                    count <= count + 1;
                end else begin
                    state <= DONE;
                    $display("[%t] MontgomeryParams: R2_mod_N calculated = %h", $time, R2_mod_N);
                end
            end
            
            DONE: begin
                done <= 1;
                busy <= 0;
                if (!start) begin
                    state <= IDLE;
                end
            end
            
            default: state <= IDLE;
        endcase
    end
end

endmodule

// ================= 参数化的模乘模块 =================
module modular_multiplier #(
    parameter WIDTH = 256
)(
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [WIDTH-1:0] a,
    input wire [WIDTH-1:0] b,
    input wire [WIDTH-1:0] N,
    input wire [WIDTH-1:0] Np,
    input wire [WIDTH-1:0] R2_mod_N,
    output reg [WIDTH-1:0] result,
    output reg done,
    output reg busy
);

// 蒙哥马利乘法状态
reg [3:0] state;
reg [WIDTH-1:0] a_reg, b_reg, N_reg;
reg [2*WIDTH:0] temp;  // 用于中间计算
reg [7:0] count;

localparam IDLE          = 4'd0;
localparam CONVERT_A     = 4'd1;
localparam CONVERT_B     = 4'd2;
localparam MONT_MUL      = 4'd3;
localparam CONVERT_BACK  = 4'd4;
localparam DONE          = 4'd5;

// 蒙哥马利乘法：计算 a * b * R^{-1} mod N
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
        result <= 0;
        done <= 0;
        busy <= 0;
        a_reg <= 0;
        b_reg <= 0;
        N_reg <= 0;
        temp <= 0;
        count <= 0;
    end else begin
        done <= 0;
        
        case (state)
            IDLE: begin
                if (start) begin
                    busy <= 1;
                    a_reg <= a;
                    b_reg <= b;
                    N_reg <= N;
                    state <= CONVERT_A;
                    count <= 0;
                    
                    // 将输入转换为蒙哥马利域
                    $display("[%t] ModularMultiplier: Starting, a=%h, b=%h, N=%h", 
                             $time, a, b, N);
                end
            end
            
            CONVERT_A: begin
                // 将a转换到蒙哥马利域：a * R2_mod_N mod N
                // 简化处理：这里需要实际的蒙哥马利乘法
                if (count == 0) begin
                    temp <= a_reg * R2_mod_N;
                    count <= 1;
                end else if (count == 1) begin
                    // 计算蒙哥马利约简
                    // m = (temp mod R) * Np mod R
                    // temp = (temp + m * N) / R
                    // 简化实现
                    a_reg <= temp % N_reg;
                    count <= 0;
                    state <= CONVERT_B;
                end
            end
            
            CONVERT_B: begin
                // 将b转换到蒙哥马利域：b * R2_mod_N mod N
                if (count == 0) begin
                    temp <= b_reg * R2_mod_N;
                    count <= 1;
                end else if (count == 1) begin
                    // 简化实现
                    b_reg <= temp % N_reg;
                    count <= 0;
                    state <= MONT_MUL;
                end
            end
            
            MONT_MUL: begin
                // 执行蒙哥马利乘法
                // 计算：a_reg * b_reg * R^{-1} mod N
                if (count == 0) begin
                    temp <= a_reg * b_reg;
                    count <= 1;
                end else if (count == 1) begin
                    // 蒙哥马利约简
                    // 实际需要完整实现
                    result <= temp % N_reg;
                    state <= CONVERT_BACK;
                    count <= 0;
                end
            end
            
            CONVERT_BACK: begin
                // 将结果转换回普通域：result * 1 mod N
                if (count == 0) begin
                    temp <= result;
                    count <= 1;
                end else if (count == 1) begin
                    // 简化实现
                    result <= temp % N_reg;
                    state <= DONE;
                end
            end
            
            DONE: begin
                done <= 1;
                busy <= 0;
                if (!start) begin
                    state <= IDLE;
                end
            end
            
            default: state <= IDLE;
        endcase
    end
end

endmodule