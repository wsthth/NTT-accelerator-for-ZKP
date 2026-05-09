// montgomery_multiplier_simple_test.v
`timescale 1ns / 1ps

module montgomery_multiplier_simple_test_tb;

// 时钟和复位信号
reg clk;
reg reset_n;

// 测试控制信号
reg start;
reg [255:0] a_mont;
reg [255:0] b_mont;
reg [255:0] N;
reg [255:0] N_prime;

// 输出信号
wire [255:0] result_mont;
wire done;

// 实例化待测试的蒙哥马利乘法器
montgomery_multiplier_256bit #(
    .TOTAL_BITS(256),
    .SEG_BITS(64)
) dut (
    .clk(clk),
    .reset_n(reset_n),
    .start(start),
    .a_mont(a_mont),
    .b_mont(b_mont),
    .N(N),
    .N_prime(N_prime),
    .result_mont(result_mont),
    .done(done)
);

// 时钟生成
always #5 clk = ~clk;  // 100MHz时钟

// 主测试流程
initial begin
    // 初始化信号
    clk = 0;
    reset_n = 0;
    start = 0;
    a_mont = 0;
    b_mont = 0;
    N = 0;
    N_prime = 0;
    
    // 打开波形文件（如果使用ModelSim等工具）
    // $dumpfile("montgomery_multiplier.vcd");
    // $dumpvars(0, montgomery_multiplier_simple_test);
    
    $display("=========================================");
    $display("Starting Montgomery Multiplier Test");
    $display("=========================================\n");
    
    // 复位
    #20 reset_n = 1;
    #50;
    
    // 测试1: 2 * 3 mod 5 = 1
    // 对于N=5，R=2^256 mod 5 = 1，所以蒙哥马利域和正常域相同
/*     a_mont = 256'h16db3787c008bbc00870a59497036f7f43e71fc1218341741c7bc7cc0ceb3313;  // 正常域的2也是蒙哥马利域的2
    b_mont = 256'h87a1d2b7448c77d0c5a8c4e7241aa9a40f3f294768bdd2611e3d89374ff16f6;  // 正常域的3也是蒙哥马利域的3
    N = 256'h30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47;
    N_prime = 256'hf57a22b791888c6bd8afcbd01833da809ede7d651eca6ac987d20782e4866389;
 */    
    
    a_mont = 256'h21d531db5e253a35f2cd61df879d90300ef9dc5630ebf2e643e3a7c9094285f;  // 正常域的2也是蒙哥马利域的2
    b_mont = 256'h1e62dd454467ada9368ca3c701e50a3543f2aad063eb23e6b67e20bb13bd199e;  // 正常域的3也是蒙哥马利域的3
    N = 256'h30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47;
    N_prime = 256'hf57a22b791888c6bd8afcbd01833da809ede7d651eca6ac987d20782e4866389;
    
    
    
    
    
    
    
    
    
    $display("Test: 2 * 3 mod 5 = 1");
    $display("  a_mont = %064h", a_mont);
    $display("  b_mont = %064h", b_mont);
    $display("  N = %064h", N);
    $display("  N_prime = %064h", N_prime);
    $display("  Expected result = 1");
    
    // 启动测试
    start = 1;
    #10 start = 0;
    
    // 等待完成
    wait(done);
    #10;
    
    // 显示结果
    $display("  Actual result = %064h", result_mont);
    
    if (result_mont == 256'd1) begin
        $display("  ✓ Test PASSED");
    end else begin
        $display("  ✗ Test FAILED");
        $display("  Expected: 0000000000000000000000000000000000000000000000000000000000000001");
        $display("  Got:      %064h", result_mont);
    end
    
    // 结束仿真
    #100;
    $display("\n=========================================");
    $display("Test Complete");
    $display("=========================================");
    $finish;
end

endmodule