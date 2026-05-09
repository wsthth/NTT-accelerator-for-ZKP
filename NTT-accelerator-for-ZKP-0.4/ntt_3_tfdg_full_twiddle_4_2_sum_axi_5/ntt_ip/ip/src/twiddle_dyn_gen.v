// 旋转因子动态生成模块（极简版，384bit基16 NTT）
module twiddle_dyn_gen(
    input clk,                  // 时钟（100MHz）
    input rst_n,                // 复位
    // 输入：NTT轮次、并行分支
    input [7:0] i,              // 高阶索引（轮次）
    input [3:0] j,              // 低阶索引（0~15，16路并行）
    // 输出：生成的旋转因子、复用标识
    output reg [383:0] twiddle, // 384bit旋转因子
    output reg reuse_flag       // 1=可复用，0=重新生成
);

// 固定参数（可通过寄存器配置，极简版直接赋值）
parameter MOD = 32'h00000D01;   // 模值3329（简化版）
parameter N = 16'h1000;         // 变换长度4096
parameter G = 32'h00000003;     // 原根3

// 子模块1：k值生成与归一化
reg [15:0] k;
reg [15:0] norm_k;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        k <= 16'd0;
        norm_k <= 16'd0;
    end else begin
        k <= 16 * i + j;                // k=16i+j
        norm_k <= k % N;                // 归一化k值
    end
end

// 子模块2：递推计算（简化版，384bit模幂运算用IP核/组合逻辑实现）
// 注：实际384bit模幂需用FPGA的乘法器IP（如Xilinx Multiplier），此处简化为占位
reg [383:0] exponent;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        exponent <= 384'd0;
        twiddle <= 384'd0;
    end else begin
        exponent <= ((MOD - 1) / N) * norm_k;  // 指数计算
        twiddle <= pow_mod(G, exponent, MOD);  // 模幂运算（调用IP核/自定义模块）
    end
end

// 子模块4：复用校验（简化版，用寄存器模拟BRAM）
reg [1:0] bram [0:N-1];  // BRAM元数据：bit1=有效位，bit0=计时器（简化为0/1）
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        reuse_flag <= 1'b0;
    end else begin
        if(bram[norm_k][1] == 1'b1 && bram[norm_k][0] == 1'b0) begin
            // 有效位=1，计时器未超时→可复用
            reuse_flag <= 1'b1;
            bram[norm_k][0] <= 1'b0;  // 刷新计时器
        end else begin
            // 不可复用，生成后标记有效位
            reuse_flag <= 1'b0;
            bram[norm_k][1] <= 1'b1;  // 有效位=1
            bram[norm_k][0] <= 1'b0;  // 计时器=0
        end
    end
end

// 模幂运算占位模块（实际需替换为硬件实现）
function [383:0] pow_mod;
    input [31:0] base;
    input [383:0] exp;
    input [31:0] mod;
    // 硬件实现逻辑：迭代乘法+模约简（用流水线乘法器）
    pow_mod = 384'd0;  // 极简版先赋值，后续替换
endfunction

endmodule

