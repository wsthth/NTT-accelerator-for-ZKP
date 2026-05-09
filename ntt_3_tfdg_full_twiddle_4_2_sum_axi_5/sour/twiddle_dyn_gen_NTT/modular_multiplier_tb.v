// modular_multiplier_tb.v
`timescale 1ns / 1ps

module modular_multiplier_tb;

// 参数
parameter DATA_WIDTH = 256;
parameter CLK_PERIOD = 10;

// 信号
reg clk;
reg reset_n;
reg start;
reg [DATA_WIDTH-1:0] a;
reg [DATA_WIDTH-1:0] b;
reg [DATA_WIDTH-1:0] modulus;
wire [DATA_WIDTH-1:0] result;
wire done;

// 测试控制
reg [7:0] test_num;
reg [31:0] cycle_count;

// 实例化
modular_multiplier_256bit dut (
    .clk(clk),
    .reset_n(reset_n),
    .start(start),
    .a(a),
    .b(b),
    .modulus(modulus),
    .result(result),
    .done(done)
);

// 时钟
initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

// 主测试
initial begin
    $display("==================================");
    $display("Modular Multiplier Test");
    $display("==================================");
    
    // 初始化
    initialize();
    
    // 测试1: 简单乘法
    test_num = 1;
    $display("\nTest %d: 2 * 3 mod 5 = 1", test_num);
    run_test(256'd2, 256'd3, 256'd5, 256'd1);
    
    // 测试2: 大数模运算
    test_num = test_num + 1;
    $display("\nTest %d: 16 * 32 mod 256 = 0", test_num);
    run_test(256'd16, 256'd32, 256'd256, 256'd0);
    
    // 测试3: 模数为0
    test_num = test_num + 1;
    $display("\nTest %d: 10 * 20 (mod 0) = 200", test_num);
    run_test(256'd10, 256'd20, 256'd0, 256'd200);
    
    // 测试4: 模数为1
    test_num = test_num + 1;
    $display("\nTest %d: 7 * 8 mod 1 = 0", test_num);
    run_test(256'd7, 256'd8, 256'd1, 256'd0);
    
    // 测试5: 零乘
    test_num = test_num + 1;
    $display("\nTest %d: 0 * 100 mod 50 = 0", test_num);
    run_test(256'd0, 256'd100, 256'd50, 256'd0);
    
    $display("\n==================================");
    $display("All tests completed");
    $display("==================================");
    
    #100;
    $finish;
end

// 初始化任务
task initialize;
begin
    reset_n = 0;
    start = 0;
    a = 0;
    b = 0;
    modulus = 0;
    test_num = 0;
    cycle_count = 0;
    
    #(CLK_PERIOD * 3);
    reset_n = 1;
    #(CLK_PERIOD * 2);
    
    $display("[%0t] Initialized", $time);
end
endtask

// 运行单个测试
task run_test;
    input [DATA_WIDTH-1:0] a_val;
    input [DATA_WIDTH-1:0] b_val;
    input [DATA_WIDTH-1:0] mod_val;
    input [DATA_WIDTH-1:0] exp_val;
    
    integer timeout;
    integer start_time;
begin
    // 设置输入
    a = a_val;
    b = b_val;
    modulus = mod_val;
    
    #(CLK_PERIOD);
    
    // 启动计算
    start_time = $time;
    start = 1;
    #(CLK_PERIOD);
    start = 0;
    
    // 等待完成
    timeout = 0;
    while (done == 0 && timeout < 100) begin
        #(CLK_PERIOD);
        timeout = timeout + 1;
    end
    
    // 检查结果
    if (done == 1) begin
        if (result === exp_val) begin
            $display("[%0t] PASS: Got %h", $time, result);
        end else begin
            $display("[%0t] FAIL: Got %h, Expected %h", $time, result, exp_val);
        end
        $display("    Time: %d cycles", ($time - start_time)/CLK_PERIOD);
    end else begin
        $display("[%0t] TIMEOUT", $time);
    end
    
    // 等待几个周期
    #(CLK_PERIOD * 5);
end
endtask

// 时钟计数
always @(posedge clk) begin
    cycle_count <= cycle_count + 1;
end

// 监视器
always @(posedge clk) begin
    if (done) begin
        $display("[%0t] Multiplier done: %h", $time, result);
    end
end

// 波形记录
initial begin
    $dumpfile("modmult_tb.vcd");
    $dumpvars(0, modular_multiplier_tb);
end

// 超时保护
initial begin
    #(10000);
    $display("\n[%0t] Simulation timeout", $time);
    $finish;
end

endmodule