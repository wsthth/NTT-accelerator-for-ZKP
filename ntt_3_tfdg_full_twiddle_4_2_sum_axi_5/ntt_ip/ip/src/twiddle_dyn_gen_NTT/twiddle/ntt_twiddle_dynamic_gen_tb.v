// ntt_twiddle_minimal_tb.v
`timescale 1ns / 1ps

module ntt_twiddle_gen_tb_simple;

// 基本参数
parameter DATA_WIDTH = 256;
parameter CLK_PERIOD = 10;

// 模块信号
reg clk;
reg reset_n;
reg start_gen;
reg mode;
reg [DATA_WIDTH-1:0] modulus;
reg [DATA_WIDTH-1:0] Np;
reg [DATA_WIDTH-1:0] R2_mod_N;
reg [DATA_WIDTH-1:0] primitive_root;
reg [DATA_WIDTH-1:0] base_twiddle;
reg [15:0] N;
reg [7:0] stage;
reg [7:0] index;

wire [DATA_WIDTH-1:0] twiddle_out;
wire gen_done;
wire gen_valid;
wire [15:0] gen_cycles;
wire [7:0] gen_latency;
wire parallel_active;
wire error;

// 实例化被测模块
ntt_twiddle_dynamic_gen #(
    .DATA_WIDTH(DATA_WIDTH),
    .MAX_MODULUS_BITS(384),
    .PARALLEL_LEVEL(4),
    .PIPELINE_DEPTH(3)
) dut (
    .clk(clk),
    .reset_n(reset_n),
    .start_gen(start_gen),
    .mode(mode),
    .modulus(modulus),
    .Np(Np),
    .R2_mod_N(R2_mod_N),
    .primitive_root(primitive_root),
    .base_twiddle(base_twiddle),
    .N(N),
    .stage(stage),
    .index(index),
    .twiddle_out(twiddle_out),
    .gen_done(gen_done),
    .gen_valid(gen_valid),
    .gen_cycles(gen_cycles),
    .gen_latency(gen_latency),
    .parallel_active(parallel_active),
    .error(error)
);

// 时钟生成
initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

// 主测试
initial begin
    $display("=== NTT旋转因子生成测试开始 ===");
    
    // 初始化
    reset_n = 0;
    start_gen = 0;
    mode = 0;
    modulus = 0;
    Np = 0;
    R2_mod_N = 0;
    primitive_root = 0;
    base_twiddle = 0;
    N = 0;
    stage = 0;
    index = 0;
    
    // 复位
    #(CLK_PERIOD*5);
    reset_n = 1;
    #(CLK_PERIOD*5);
    $display("[%0t] 复位完成", $time);
  





  
    // 测试1: 简单功能测试
    $display("\n测试1: 简单功能测试");
/*     modulus = 17;
    
    Np = 256'hf0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f;      // -17^{-1} mod 16 = 15
    R2_mod_N = 1; // 16^2 mod 17 = 256 mod 17 = 1
 */    
    modulus = 256'd5192296858534827628530496329220105;

    
    Np = 256'd18266241786370922533667369871336683659861493350625102121987009938550580605383;      // -17^{-1} mod 16 = 15
    R2_mod_N = 256'd121029087867608368152576; // 16^2 mod 17 = 256 mod 17 = 1
    
    
    
    
    primitive_root = 5;
    // base_twiddle = 9; // 3^2 mod 17 = 9   （因为 3^{(17-1)/8} = 3² = 9 mod 17）
    base_twiddle = 256'd700826330113176447950373949728490; // 3^2 mod 17 = 9   （因为 3^{(17-1)/8} = 3² = 9 mod 17）
    N = 8;
    stage = 0;
    index = 0;
    mode = 0;
    
    $display("配置: 模数=17, N=8, base_twiddle=9, stage=0, index=0");
    
    // 启动生成
    start_gen = 1;
    #(CLK_PERIOD);
    start_gen = 0;
    
    // 等待完成
    wait(gen_done == 1);
    #(CLK_PERIOD);
    
    $display("结果: %h, gen_valid=%b", twiddle_out, gen_valid);
    
    if (gen_valid && twiddle_out == 1) begin
        $display("✅ 测试1通过");
    end else begin
        $display("❌ 测试1失败");
    end
    
    #(CLK_PERIOD*10);
 





 
    // 测试2: 不同索引
    $display("\n测试2: 不同索引测试");
    index = 1;
    
    $display("配置: stage=0, index=1");
    
    // 启动生成
    start_gen = 1;
    #(CLK_PERIOD);
    start_gen = 0;
    
    // 等待完成
    wait(gen_done == 1);
    #(CLK_PERIOD);
    $display("结果: %h, gen_valid=%b", twiddle_out, gen_valid);
    $display("✅ 测试2完成");
    
    #(CLK_PERIOD*10);







    
    // 测试3: 不同阶段
    $display("\n测试3: 不同阶段测试");
    stage = 1;
    index = 0;
    
    $display("配置: stage=1, index=0");
    
    // 启动生成
    start_gen = 1;
    #(CLK_PERIOD);
    start_gen = 0;
    
    // 等待完成
    wait(gen_done == 1);
    #(CLK_PERIOD);
    
    $display("结果: %h, gen_valid=%b", twiddle_out, gen_valid);
    $display("✅ 测试3完成");
    
    // 结束
    $display("\n=== 所有测试完成 ===");
    #(CLK_PERIOD*10);
    $finish;
end

// 波形记录
initial begin
    $dumpfile("ntt_twiddle_minimal_tb.vcd");
    $dumpvars(0, ntt_twiddle_gen_tb_simple);
end

// 超时保护
initial begin
    #(10000); // 10us超时
    $display("\n[%0t] 仿真超时", $time);
    $finish;
end

endmodule