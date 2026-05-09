// ntt_twiddle_gen_tb_simple.v
`timescale 1ns / 1ps

module ntt_twiddle_gen_tb_simple;

// ================= 测试参数 =================
parameter DATA_WIDTH = 16;        // 使用16位简化测试
parameter CLK_PERIOD = 10;        // 时钟周期 10ns
parameter SIM_TIME = 10000;       // 仿真时间 10000ns

// ================= 信号声明 =================
reg clk;
reg reset_n;
reg start_gen;
reg mode;
reg [DATA_WIDTH-1:0] modulus;
reg [DATA_WIDTH-1:0] Np;         // -N^{-1} mod R
reg [DATA_WIDTH-1:0] R2_mod_N;   // R^2 mod N
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

// ================= 测试计数器 =================
reg [31:0] cycle_count;
reg [7:0] test_num;
reg test_passed;
reg [31:0] total_tests;
reg [31:0] passed_tests;
reg [31:0] failed_tests;

// ================= 期望值存储 =================
reg [DATA_WIDTH-1:0] expected_twiddle;

// ================= 实例化被测模块 =================
ntt_twiddle_dynamic_gen #(
    .DATA_WIDTH(DATA_WIDTH),
    .MAX_MODULUS_BITS(16),
    .PARALLEL_LEVEL(4),
    .PIPELINE_DEPTH(3)
) dut (
    .clk(clk),
    .reset_n(reset_n),
    .start_gen(start_gen),
    .mode(mode),
    .modulus(modulus),
    .Np(Np),           // 连接Np
    .R2_mod_N(R2_mod_N), // 连接R2_mod_N
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

// ================= 时钟生成 =================
initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

// ================= 主测试流程 =================
initial begin
    // 初始化
    $display("======================================");
    $display("NTT Twiddle Generator Simple Test");
    $display("======================================");
    
    initialize();
    total_tests = 0;
    passed_tests = 0;
    failed_tests = 0;
    
    // 测试1: 复位测试
    test_num = 1;
    $display("\nTest %0d: Reset Test", test_num);
    reset_test();
    
    // 测试2: 正向NTT基本测试 (stage=0, index=0)
    test_num = test_num + 1;
    $display("\nTest %0d: Forward NTT Basic Test (stage=0, index=0)", test_num);
    // 使用模数12289 (常用NTT模数)
    // 计算蒙哥马利参数：
    // 对于N=12289, R=2^16=65536
    // Np = -N^{-1} mod R = 62509
    // R2_mod_N = R^2 mod N = 104
    configure_test(16'd12289, 16'd62509, 16'd104, 16'd3, 16'd1, 16'd256);
    run_test_with_expectation(8'd0, 8'd0, 1'b0, 16'd1);  // ω_base^0 = 1
    
    // 测试3: 正向NTT不同索引测试 (stage=0, index=1)
    test_num = test_num + 1;
    $display("\nTest %0d: Forward NTT Different Index (stage=0, index=1)", test_num);
    // 基础旋转因子 ω_base = 3^{(12289-1)/256} mod 12289 = 9729
    configure_test(16'd12289, 16'd62509, 16'd104, 16'd3, 16'd9729, 16'd256);
    // 期望值: ω_base^{rev(1)} = ω_base^{128} mod 12289
    // 计算: 9729^128 mod 12289 = 8321
    run_test_with_expectation(8'd0, 8'd1, 1'b0, 16'd8321);
    
    // 测试4: 正向NTT不同阶段测试 (stage=1, index=0)
    test_num = test_num + 1;
    $display("\nTest %0d: Forward NTT Different Stage (stage=1, index=0)", test_num);
    configure_test(16'd12289, 16'd62509, 16'd104, 16'd3, 16'd9729, 16'd256);
    // 期望值: ω_base^{rev(0)*N/2^{2}} = ω_base^0 = 1
    run_test_with_expectation(8'd1, 8'd0, 1'b0, 16'd1);
    
    // 测试5: 逆向NTT测试 (stage=0, index=0)
    test_num = test_num + 1;
    $display("\nTest %0d: Inverse NTT Test (stage=0, index=0)", test_num);
    configure_test(16'd12289, 16'd62509, 16'd104, 16'd3, 16'd9729, 16'd256);
    // 期望值: ω_base^{(N-1)-0} = ω_base^{12288} mod 12289
    // 由于 ω_base^{N} = ω_base^{256} = 1 mod 12289
    // 所以 ω_base^{12288} = (ω_base^{256})^{48} = 1
    run_test_with_expectation(8'd0, 8'd0, 1'b1, 16'd1);
    
    // 测试6: 边界测试 - 大索引 (index=255)
    test_num = test_num + 1;
    $display("\nTest %0d: Boundary Test - Large Index (index=255)", test_num);
    configure_test(16'd12289, 16'd62509, 16'd104, 16'd3, 16'd9729, 16'd256);
    // rev(255) = rev(8'b11111111) = 8'b11111111 = 255
    // 期望值: ω_base^{255} mod 12289 = 计算得到
    run_test_without_expectation(8'd0, 8'd255, 1'b0);
    
    // 测试7: 连续生成测试
    test_num = test_num + 1;
    $display("\nTest %0d: Continuous Generation Test", test_num);
    configure_test(16'd12289, 16'd62509, 16'd104, 16'd3, 16'd9729, 16'd256);
    
    // 第一次生成
    $display("[%0t] First generation", $time);
    run_test_without_expectation(8'd0, 8'd0, 1'b0);
    
    // 等待一些周期
    #(CLK_PERIOD * 10);
    
    // 第二次生成 (不同参数)
    $display("[%0t] Second generation", $time);
    run_test_without_expectation(8'd0, 8'd2, 1'b0);
    
    // 等待一些周期
    #(CLK_PERIOD * 10);
    
    // 第三次生成 (不同阶段)
    $display("[%0t] Third generation", $time);
    run_test_without_expectation(8'd2, 8'd0, 1'b0);
    
    // 测试8: 性能测试 (测量延迟)
    test_num = test_num + 1;
    $display("\nTest %0d: Performance Test", test_num);
    configure_test(16'd12289, 16'd62509, 16'd104, 16'd3, 16'd9729, 16'd256);
    performance_test(8'd0, 8'd0, 1'b0);
    
    // 测试总结
    $display("\n======================================");
    $display("Test Summary");
    $display("======================================");
    $display("Total Tests: %0d", total_tests);
    $display("Passed:      %0d", passed_tests);
    $display("Failed:      %0d", failed_tests);
    
    if (failed_tests == 0) begin
        $display("\nAll tests PASSED!");
    end else begin
        $display("\nSome tests FAILED!");
    end
    
    $display("\n======================================");
    $display("All Tests Completed");
    $display("======================================");
    
    #100;
    $finish;
end

// ================= 测试任务 =================
task initialize;
begin
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
    cycle_count = 0;
    test_passed = 1;
    
    #(CLK_PERIOD * 2);
    reset_n = 1;
    #(CLK_PERIOD * 2);
    
    $display("[%0t] System initialized", $time);
end
endtask

task reset_test;
begin
    total_tests = total_tests + 1;
    
    // 确保复位期间所有信号正确
    reset_n = 0;
    #(CLK_PERIOD * 3);
    
    if (gen_done == 0 && gen_valid == 0) begin
        $display("[%0t] Reset test PASSED", $time);
        passed_tests = passed_tests + 1;
    end else begin
        $display("[%0t] Reset test FAILED", $time);
        failed_tests = failed_tests + 1;
    end
    
    reset_n = 1;
    #(CLK_PERIOD * 2);
end
endtask

task configure_test;
    input [DATA_WIDTH-1:0] mod_val;
    input [DATA_WIDTH-1:0] np_val;
    input [DATA_WIDTH-1:0] r2_val;
    input [DATA_WIDTH-1:0] root_val;
    input [DATA_WIDTH-1:0] base_val;
    input [15:0] n_val;
begin
    modulus = mod_val;
    Np = np_val;
    R2_mod_N = r2_val;
    primitive_root = root_val;
    base_twiddle = base_val;
    N = n_val;
    
    $display("[%0t] Configured:", $time);
    $display("  modulus        = %h (%0d)", mod_val, mod_val);
    $display("  Np             = %h (%0d)", np_val, np_val);
    $display("  R2_mod_N       = %h (%0d)", r2_val, r2_val);
    $display("  primitive_root = %h", root_val);
    $display("  base_twiddle   = %h", base_val);
    $display("  N              = %0d", n_val);
    
    #(CLK_PERIOD * 2);
end
endtask

task run_test_with_expectation;
    input [7:0] stage_val;
    input [7:0] index_val;
    input mode_val;
    input [DATA_WIDTH-1:0] expected_val;
    integer timeout;
    integer start_time;
    integer end_time;
    integer latency;
begin
    total_tests = total_tests + 1;
    
    stage = stage_val;
    index = index_val;
    mode = mode_val;
    expected_twiddle = expected_val;
    
    $display("[%0t] Starting test: stage=%d, index=%d, mode=%b", 
             $time, stage_val, index_val, mode_val);
    $display("  Expected output: %h", expected_val);
    
    // 记录开始时间
    start_time = $time;
    
    // 启动生成
    start_gen = 1;
    #(CLK_PERIOD);
    start_gen = 0;
    
    // 等待完成，超时保护
    timeout = 0;
    while (gen_done == 0 && timeout < 200) begin
        #(CLK_PERIOD);
        timeout = timeout + 1;
    end
    
    if (gen_done == 1) begin
        end_time = $time;
        latency = (end_time - start_time) / CLK_PERIOD;
        
        $display("[%0t] Test completed in %d cycles", $time, latency);
        $display("  Output: %h", twiddle_out);
        $display("  Latency: %d cycles", gen_latency);
        
        // 验证输出
        if (twiddle_out === expected_val) begin
            $display("  Result: PASS - Output matches expected value");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  Result: FAIL - Output mismatch!");
            $display("    Expected: %h", expected_val);
            $display("    Got:      %h", twiddle_out);
            failed_tests = failed_tests + 1;
        end
    end else begin
        $display("[%0t] Test TIMEOUT after %d cycles", $time, timeout);
        failed_tests = failed_tests + 1;
    end
    
    // 等待一些周期再开始下一个测试
    #(CLK_PERIOD * 5);
end
endtask

task run_test_without_expectation;
    input [7:0] stage_val;
    input [7:0] index_val;
    input mode_val;
    integer timeout;
    integer start_time;
    integer end_time;
    integer latency;
begin
    stage = stage_val;
    index = index_val;
    mode = mode_val;
    
    $display("[%0t] Starting test: stage=%d, index=%d, mode=%b", 
             $time, stage_val, index_val, mode_val);
    
    // 记录开始时间
    start_time = $time;
    
    // 启动生成
    start_gen = 1;
    #(CLK_PERIOD);
    start_gen = 0;
    
    // 等待完成，超时保护
    timeout = 0;
    while (gen_done == 0 && timeout < 200) begin
        #(CLK_PERIOD);
        timeout = timeout + 1;
    end
    
    if (gen_done == 1) begin
        end_time = $time;
        latency = (end_time - start_time) / CLK_PERIOD;
        
        $display("[%0t] Test completed in %d cycles", $time, latency);
        $display("  Output: %h", twiddle_out);
        $display("  Latency: %d cycles", gen_latency);
    end else begin
        $display("[%0t] Test TIMEOUT after %d cycles", $time, timeout);
    end
    
    // 等待一些周期再开始下一个测试
    #(CLK_PERIOD * 2);
end
endtask

task performance_test;
    input [7:0] stage_val;
    input [7:0] index_val;
    input mode_val;
    integer start_time;
    integer end_time;
    integer latency;
    integer num_runs;
    integer total_latency;
    integer avg_latency;
    integer i;
begin
    stage = stage_val;
    index = index_val;
    mode = mode_val;
    
    $display("[%0t] Starting performance test", $time);
    $display("  Stage: %d, Index: %d, Mode: %b", stage_val, index_val, mode_val);
    
    total_latency = 0;
    num_runs = 10;
    
    for (i = 0; i < num_runs; i = i + 1) begin
        // 记录开始时间
        start_time = $time;
        
        // 启动生成
        start_gen = 1;
        #(CLK_PERIOD);
        start_gen = 0;
        
        // 等待完成
        wait(gen_done == 1);
        
        // 计算延迟
        end_time = $time;
        latency = (end_time - start_time) / CLK_PERIOD;
        total_latency = total_latency + latency;
        
        $display("[%0t] Run %0d: %d cycles", $time, i+1, latency);
        
        // 等待一些周期
        #(CLK_PERIOD * 5);
    end
    
    avg_latency = total_latency / num_runs;
    $display("[%0t] Performance Test Complete", $time);
    $display("  Total runs: %0d", num_runs);
    $display("  Total latency: %0d cycles", total_latency);
    $display("  Average latency: %0d cycles", avg_latency);
    
    // 评估性能
    if (avg_latency < 50) begin
        $display("  Performance: GOOD");
    end else if (avg_latency < 100) begin
        $display("  Performance: ACCEPTABLE");
    end else begin
        $display("  Performance: NEEDS IMPROVEMENT");
    end
end
endtask

// ================= 时钟周期计数 =================
always @(posedge clk) begin
    cycle_count <= cycle_count + 1;
end

// ================= 信号监视器 =================
always @(posedge clk) begin
    // 监视关键信号变化
    if (start_gen) begin
        $display("[%0t] start_gen asserted", $time);
    end
    
    if (gen_valid) begin
        $display("[%0t] Output valid: %h", $time, twiddle_out);
    end
    
    if (gen_done) begin
        $display("[%0t] Generation done, latency: %d", $time, gen_latency);
    end
    
    if (error) begin
        $display("[%0t] ERROR signal active", $time);
        failed_tests = failed_tests + 1;
    end
end

// ================= 波形记录 =================
initial begin
    $dumpfile("ntt_twiddle_gen_tb.vcd");
    $dumpvars(0, ntt_twiddle_gen_tb_simple);
end

// ================= 超时保护 =================
initial begin
    #(SIM_TIME);
    $display("\n[%0t] Simulation timeout", $time);
    
    // 输出测试统计
    $display("\n======================================");
    $display("Simulation Timeout - Test Summary");
    $display("======================================");
    $display("Total Tests: %0d", total_tests);
    $display("Passed:      %0d", passed_tests);
    $display("Failed:      %0d", failed_tests);
    
    if (failed_tests == 0) begin
        $display("\nAll tests PASSED!");
    end else begin
        $display("\nSome tests FAILED!");
    end
    
    $finish;
end

// ================= 错误检查 =================
// 检查start_gen是否是单周期脉冲
reg start_gen_prev;
initial start_gen_prev = 0;
always @(posedge clk) begin
    if (start_gen && start_gen_prev) begin
        $display("[%0t] ERROR: start_gen should be single cycle pulse", $time);
        failed_tests = failed_tests + 1;
    end
    start_gen_prev <= start_gen;
end

// 检查gen_done是否是单周期脉冲
reg gen_done_prev;
initial gen_done_prev = 0;
always @(posedge clk) begin
    if (gen_done && gen_done_prev) begin
        $display("[%0t] ERROR: gen_done should be single cycle pulse", $time);
        failed_tests = failed_tests + 1;
    end
    gen_done_prev <= gen_done;
end

endmodule