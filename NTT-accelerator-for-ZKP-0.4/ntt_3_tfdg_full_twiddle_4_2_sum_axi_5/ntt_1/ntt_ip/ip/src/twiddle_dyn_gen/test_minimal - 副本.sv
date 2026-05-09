// test_minimal.sv - 最简测试平台
`timescale 1ns/1ps

module test_minimal;

// 参数
parameter DATA_WIDTH = 32;
parameter MODULUS_WIDTH = 16;
parameter CLK_PERIOD = 10;  // 100MHz

// 时钟和复位
reg clk = 0;
reg reset_n = 0;
always #(CLK_PERIOD/2) clk = ~clk;

// DUT
wire [DATA_WIDTH-1:0] tw_real, tw_imag;
wire gen_done, gen_valid;
wire [15:0] gen_cycles;
wire [7:0] gen_latency;
wire parallel_active, error;

// 控制信号
reg start_gen = 0;
reg mode = 0;  // 单次模式
reg [1:0] precision = 2'b10;  // 高精度
reg [MODULUS_WIDTH-1:0] modulus = 12289;
reg [15:0] N = 256;
reg [7:0] stage = 0;
reg [7:0] index = 0;

// 实例化设计
twiddle_dynamic_gen #(
    .DATA_WIDTH(DATA_WIDTH),
    .MODULUS_WIDTH(MODULUS_WIDTH),
    .MAX_MODULUS(12289),
    .PARALLEL_LEVEL(4),
    .PIPELINE_DEPTH(3)
) dut (
    .clk(clk),
    .reset_n(reset_n),
    .start_gen(start_gen),
    .mode(mode),
    .precision(precision),
    .modulus(modulus),
    .N(N),
    .stage(stage),
    .index(index),
    .twiddle_real(tw_real),
    .twiddle_imag(tw_imag),
    .gen_done(gen_done),
    .gen_valid(gen_valid),
    .gen_cycles(gen_cycles),
    .gen_latency(gen_latency),
    .parallel_active(parallel_active),
    .error(error)
);

// 测试序列
initial begin
    // 初始化VCD文件
    $dumpfile("twiddle_minimal.vcd");
    $dumpvars(0, test_minimal);
    
    $display("=== 开始旋转因子动态生成模块测试 ===");
    $display("时间：%t", $time);
    
    // 1. 复位
    $display("[1] 复位...");
    reset_n = 0;
    #100;
    reset_n = 1;
    #20;
    
    // 2. 测试1：生成第一个旋转因子 (W_256^0 = 1 + 0i)
    $display("[2] 测试1：生成 W_256^0...");
    modulus = 12289;
    N = 256;
    stage = 0;
    index = 0;
    
    start_gen = 1;
    @(posedge clk);
    start_gen = 0;
    
    wait(gen_done);
    $display("    生成完成，周期数：%0d", gen_cycles);
    $display("    结果：real=%h (%d), imag=%h (%d)", 
             tw_real, tw_real, tw_imag, tw_imag);
    
    // 3. 测试2：生成不同索引的旋转因子
    $display("[3] 测试2：生成 W_256^1...");
    index = 1;
    start_gen = 1;
    @(posedge clk);
    start_gen = 0;
    
    wait(gen_done);
    $display("    结果：real=%h (%d), imag=%h (%d)", 
             tw_real, tw_real, tw_imag, tw_imag);
    
    // 4. 测试3：生成不同阶段的旋转因子
    $display("[4] 测试3：生成不同阶段...");
    for (int i = 0; i < 4; i++) begin
        stage = i;
        index = i * 2;
        start_gen = 1;
        @(posedge clk);
        start_gen = 0;
        
        wait(gen_done);
        #10;
    end
    
    // 5. 测试4：不同模数（创新点1验证）
    $display("[5] 测试4：不同模数（通用化验证）...");
    modulus = 7681;  // 不同模数
    stage = 2;
    index = 5;
    start_gen = 1;
    @(posedge clk);
    start_gen = 0;
    
    wait(gen_done);
    $display("    模数：%d，结果：real=%h, imag=%h", 
             modulus, tw_real, tw_imag);
    
    // 6. 性能测试
    $display("[6] 性能测试：连续生成10个旋转因子...");
    mode = 1;  // 连续模式
    start_gen = 1;
    
    for (int i = 0; i < 10; i++) begin
        index = i;
        wait(gen_done);
        $display("    [%0d] 延迟：%0d 周期", i, gen_latency);
        #10;
    end
    
    mode = 0;
    start_gen = 0;
    
    // 总结
    $display("\n=== 测试总结 ===");
    $display("所有测试完成");
    $display("最终错误状态：%b", error);
    
    if (error)
        $display("❌ 测试失败：检测到错误");
    else
        $display("✅ 测试通过：无错误");
    
    $finish;
end

// 超时检测
initial begin
    #(CLK_PERIOD * 10000);  // 10us超时
    $display("❌ 超时：仿真时间过长");
    $finish;
end

endmodule
