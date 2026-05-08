// ============================================================================
// 文件名: tb_montgomery_top.v
// 描述: 修正的蒙哥马利模约简顶层模块仿真测试
// 更新说明:
// 1. 适配montgomery_top.v的新接口
// 2. 添加了更详细的监控和验证
// 3. 修复了task中的语法错误
// ============================================================================
`timescale 1ns/1ps

module tb_montgomery_top();

// ============================================================================
// 参数定义
// ============================================================================
localparam CLK_PERIOD = 10;  // 100MHz时钟周期
localparam TOTAL_BITS = 256;

// ============================================================================
// 信号定义
// ============================================================================
reg clk;
reg rst_n;
reg start;
wire done;

reg [TOTAL_BITS-1:0] expected_result;  // Python计算结果
reg test_pass;
reg [31:0] error_count;

// 添加层次化引用以监控内部信号
wire [TOTAL_BITS-1:0] mont_result;
wire [TOTAL_BITS-1:0] internal_error_expected;
wire internal_error_detected;

// ============================================================================
// DUT实例化
// ============================================================================
montgomery_top dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .done(done)
);

// 层次化引用到DUT内部信号
assign mont_result = dut.mont_result;
assign internal_error_expected = dut.error_expected;
assign internal_error_detected = dut.error_detected;

// ============================================================================
// 时钟生成
// ============================================================================
initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

// ============================================================================
// 测试向量生成任务
// ============================================================================
task generate_test_vector;
    begin
        // 这里应该填入从Python代码计算得到的实际测试向量
        // 注意：这些值应该与montgomery_top.v中的参数一致
        
        // 预期结果 (从Python计算得到)
        // 对于示例的BN254测试，这个值应该匹配
        expected_result = 256'h1c4d8e1b9f8a3d2c5b6a7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9;
        
        $display("[TEST] 生成测试向量");
        $display("[TEST] 预期结果: 0x%h", expected_result);
    end
endtask

// ============================================================================
// 复位任务
// ============================================================================
task reset_system;
    begin
        rst_n = 1'b0;
        start = 1'b0;
        test_pass = 1'b0;
        error_count = 0;
        #(CLK_PERIOD * 5);
        rst_n = 1'b1;
        #(CLK_PERIOD * 2);
        $display("[TEST] 系统复位完成");
    end
endtask

// ============================================================================
// 运行单次测试任务
// ============================================================================
task run_single_test;
    begin
        $display("[TEST] 开始蒙哥马利模约简测试...");
        
        // 等待一个时钟周期
        #(CLK_PERIOD);
        
        // 启动计算
        start = 1'b1;
        #(CLK_PERIOD);
        start = 1'b0;
        
        // 等待计算完成
        wait(done == 1'b1);
        $display("[TEST] 计算完成，done信号变高");
        
        // 等待几个周期让结果稳定
        #(CLK_PERIOD * 10);
    end
endtask

// ============================================================================
// 结果验证任务
// ============================================================================
task verify_result;
    begin
        $display("[TEST] 验证计算结果...");
        
        // 等待一段时间后检查
        #(CLK_PERIOD * 5);
        
        // 检查内部错误检测信号
        if (internal_error_detected) begin
            $display("[TEST] ❌ 内部错误检测到不一致!");
            $display("[TEST]   计算值: 0x%h", mont_result);
            $display("[TEST]   预期值: 0x%h", internal_error_expected);
            error_count = error_count + 1;
            test_pass = 1'b0;
        end else begin
            $display("[TEST] ✅ 内部验证通过");
            test_pass = 1'b1;
        end
        
        // 额外验证：直接比较结果
        if (mont_result === expected_result) begin
            $display("[TEST] ✅ 直接比较验证通过");
            $display("[TEST]   计算值: 0x%h", mont_result);
            $display("[TEST]   预期值: 0x%h", expected_result);
        end else begin
            $display("[TEST] ❌ 直接比较验证失败!");
            $display("[TEST]   计算值: 0x%h", mont_result);
            $display("[TEST]   预期值: 0x%h", expected_result);
            error_count = error_count + 1;
            test_pass = 1'b0;
        end
    end
endtask

// ============================================================================
// 运行多次测试任务
// ============================================================================
task run_multiple_tests;
    input integer num_tests;
    integer i;
    begin
        $display("[TEST] 运行 %0d 次测试", num_tests);
        
        for (i = 0; i < num_tests; i = i + 1) begin
            $display("[TEST] --- 测试 %0d ---", i+1);
            
            // 重新生成测试向量（如果需要不同测试）
            generate_test_vector;
            
            // 运行单次测试
            run_single_test;
            
            // 验证结果
            verify_result;
            
            // 重置以准备下一次测试
            #(CLK_PERIOD * 5);
            start = 1'b0;
            #(CLK_PERIOD * 5);
        end
    end
endtask

// ============================================================================
// 主测试过程
// ============================================================================
initial begin
    // 初始化
    $display("==============================================");
    $display("蒙哥马利模约简仿真测试");
    $display("==============================================");
    
    // 生成测试向量
    generate_test_vector;
    
    // 复位系统
    reset_system;
    
    // 运行测试（可以改为多次测试）
    run_single_test;
    
    // 验证结果
    verify_result;
    
    // 可以运行多次测试
    // run_multiple_tests(3);
    
    // 显示测试结果摘要
    $display("\n==============================================");
    $display("测试结果摘要:");
    $display("测试状态: %s", test_pass ? "通过" : "失败");
    $display("错误计数: %0d", error_count);
    $display("模拟时间: %0t ns", $time);
    $display("==============================================");
    
    // 结束仿真
    #(CLK_PERIOD * 10);
    
    if (error_count == 0) begin
        $display("✅ 所有测试通过!");
    end else begin
        $display("❌ 发现 %0d 个错误!", error_count);
    end
    
    $finish;
end

// ============================================================================
// 监控关键信号变化
// ============================================================================
initial begin
    $monitor("Time=%0t: start=%b, done=%b, mont_result=0x%h, error_detected=%b", 
             $time, start, done, mont_result, internal_error_detected);
end

// ============================================================================
// 波形存储
// ============================================================================
initial begin
    // VCD波形文件存储
    $dumpfile("montgomery_sim.vcd");
    $dumpvars(0, tb_montgomery_top);
    
    // 也可以选择性地存储信号
    // $dumpvars(1, dut);  // 存储DUT的所有信号
    
    $display("[SIM] 波形文件初始化完成");
end

// ============================================================================
// 超时保护
// ============================================================================
initial begin
    #(CLK_PERIOD * 10000);  // 100us超时
    $display("[ERROR] 仿真超时!");
    $display("[ERROR] 当前状态: start=%b, done=%b", start, done);
    $finish;
end

// ============================================================================
// 错误检查
// ============================================================================
// 检查未知值
always @(posedge clk) begin
    if (mont_result === {TOTAL_BITS{1'bx}}) begin
        $display("[WARNING] mont_result 包含未知值 X!");
    end
end

// 检查复位后的状态
initial begin
    #(CLK_PERIOD * 10);
    if (rst_n && (mont_result !== {TOTAL_BITS{1'b0}})) begin
        $display("[WARNING] 复位后mont_result不是全0!");
    end
end

endmodule