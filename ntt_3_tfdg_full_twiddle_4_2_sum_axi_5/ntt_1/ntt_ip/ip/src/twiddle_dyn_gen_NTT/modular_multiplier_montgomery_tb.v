// ============================================================================
// Testbench for Modular Multiplier
// ============================================================================

module modular_multiplier_montgomery_tb;

// Clock and reset
reg clk;
reg rst_n;

// DUT inputs
reg start;
reg [255:0] a;
reg [255:0] b;
reg [255:0] N;
reg [255:0] Np;
reg [255:0] R2_mod_N;

// DUT outputs
wire [255:0] result;
wire done;
wire busy;

// 实例化被测模块
modular_multiplier_256bit dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .a(a),
    .b(b),
    .N(N),
    .Np(Np),
    .R2_mod_N(R2_mod_N),
    .result(result),
    .done(done),
    .busy(busy)
);

// 时钟生成
always #5 clk = ~clk;  // 100MHz时钟

// 测试主程序
initial begin
    // 初始化
    clk = 0;
    rst_n = 0;
    start = 0;
    a = 256'd0;
    b = 256'd0;
    
    // 常用的NTT模数 (2^256 - 2^224 + 2^192 + 2^96 - 1)
    // N = 256'hFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF;
    N = 256'h30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47;
    // 预计算值 (这里用示例值，实际使用时需要正确计算)
    // Np = -N^{-1} mod 2^256
    // Np = 256'hFFFFFFFF00000002000000000000000000000001000000000000000000000001;
    Np = 256'hf57a22b791888c6bd8afcbd01833da809ede7d651eca6ac987d20782e4866389;
    // R^2 mod N = 2^512 mod N
    // R2_mod_N = 256'h0000000400000000000000000000000000000000000000000000000000000000;
   
    R2_mod_N = 256'h6d89f71cab8351f47ab1eff0a417ff6b5e71911d44501fbf32cfc5b538afa89;
    // 复位
    #20 rst_n = 1;
    
    $display("=========================================");
    $display("开始测试256位蒙哥马利模乘器");
    $display("模数 N = %h", N);
    $display("=========================================");
    
    // 测试用例1: 小数字
    $display("\n测试用例1: 小数字乘法");
    a = 256'd12345;
    b = 256'd67890;
    
/*     a = 256'h75bcd15;
    b = 256'h3ade68b1;
 */    
    start = 1;
    #10 start = 0;
    
    wait(done);
    #10;
    $display("a = %d, b = %d", a, b);
    $display("计算结果: %h", result);
    $display("预期: (12345 * 67890) mod N");
    
    // 测试用例2: 边界情况 (a = N-1, b = N-1)
    $display("\n测试用例2: 边界情况 (N-1) * (N-1) mod N");
/*     a = N - 1;
    b = N - 1;
 */   
 
/*     a = 256'h75bcd15;
    b = 256'h3ade68b1;
 */    
    a = 256'h1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
    b = 256'hfedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321;
    
    
    
    start = 1;
    #10 start = 0;
    
    wait(done);
    #10;
    $display("a = N-1 = %h", a);
    $display("b = N-1 = %h", b);
    $display("计算结果: %h", result);
    $display("预期: ((N-1)^2 mod N) = 1");
    
    // 测试用例3: 随机数字
    $display("\n测试用例3: 随机数字");
    a = 256'h1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF;
    b = 256'hFEDCBA0987654321FEDCBA0987654321FEDCBA0987654321FEDCBA0987654321;
    start = 1;
    #10 start = 0;
    
    wait(done);
    #10;
    $display("a = %h", a);
    $display("b = %h", b);
    $display("计算结果: %h", result);
    
    // 测试用例4: a = 1, b = 任意数
    $display("\n测试用例4: 乘以1");
    a = 256'd1;
    b = 256'h1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF;
    start = 1;
    #10 start = 0;
    
    wait(done);
    #10;
    $display("a = 1");
    $display("b = %h", b);
    $display("计算结果: %h", result);
    $display("预期: b mod N = %h", b % N);
    
    // 测试用例5: a = 0, b = 任意数
    $display("\n测试用例5: 乘以0");
    a = 256'd0;
    b = 256'h1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF;
    start = 1;
    #10 start = 0;
    
    wait(done);
    #10;
    $display("a = 0");
    $display("b = %h", b);
    $display("计算结果: %h", result);
    $display("预期: 0");
    
    // 测试用例6: 连续操作
    $display("\n测试用例6: 连续乘法操作");
    repeat (3) begin
        a = {$random, $random, $random, $random, $random, $random, $random, $random};
        b = {$random, $random, $random, $random, $random, $random, $random, $random};
        start = 1;
        #10 start = 0;
        
        wait(done);
        #20;
        $display("a = %h", a);
        $display("b = %h", b);
        $display("计算结果: %h", result);
    end
    
    $display("\n=========================================");
    $display("所有测试完成!");
    $display("=========================================");
    #100 $finish;
end

// 监控信号变化
initial begin
    $timeformat(-9, 2, " ns", 10);
    $monitor("Time=%t: start=%b, busy=%b, done=%b, result=%h",
             $time, start, busy, done, result);
end

/* // 生成波形文件
initial begin
    $dumpfile("modular_multiplier_tb.vcd");
    $dumpvars(0, modular_multiplier_tb);
end
 */
endmodule