// montgomery_multiplier_testbench.v
`timescale 1ns / 1ps

module montgomery_multiplier_testbench;

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

// 计算蒙哥马利乘法的参考模型（行为级）
function [255:0] montgomery_multiply_ref;
    input [255:0] a_mont;
    input [255:0] b_mont;
    input [255:0] N;
    input [255:0] N_prime;
    
    reg [511:0] t;       // 512位中间乘积
    reg [255:0] m;       // 中间值
    reg [511:0] mN;      // m * N (512位)
    reg [511:0] u;       // 中间结果
    reg [255:0] result;  // 最终结果
    
    begin
        // 步骤1: 计算 t = a_mont * b_mont
        t = a_mont * b_mont;
        
        // 步骤2: 计算 m = (t mod R) * N_prime mod R
        // R = 2^256，所以 t mod R 就是 t 的低256位
        m = (t[255:0] * N_prime);
        
        // 步骤3: 计算 u = (t + m * N) / R
        // 注意：m 只取低256位
        mN = m[255:0] * N;
        u = t + mN;
        
        // 除以 R (2^256) 相当于右移256位
        result = u[511:256];
        
        // 步骤4: 如果 result >= N，则减去 N
        if (result >= N)
            result = result - N;
        
        montgomery_multiply_ref = result;
    end
endfunction

// 从日志中提取的预计算参数（用于测试）
function [255:0] get_N_prime;
    input [255:0] N_val;
    begin
        if (N_val == 256'd5)
            get_N_prime = 256'h3333333333333333333333333333333333333333333333333333333333333333;
        else if (N_val == 256'd7)
            get_N_prime = 256'h9249249249249249249249249249249249249249249249249249249249249249;
        else if (N_val == 256'd11)
            get_N_prime = 256'h745d1745d1745d1745d1745d1745d1745d1745d1745d1745d1745d1745d1745d;
        else
            get_N_prime = 256'h0;
    end
endfunction

// 获取R_mod_N（用于转换到蒙哥马利域）
function [255:0] get_R_mod_N;
    input [255:0] N_val;
    begin
        if (N_val == 256'd5)
            get_R_mod_N = 256'h1;
        else if (N_val == 256'd7)
            get_R_mod_N = 256'h2;
        else if (N_val == 256'd11)
            get_R_mod_N = 256'h9;
        else
            get_R_mod_N = 256'h0;
    end
endfunction

// 将普通数转换为蒙哥马利域
function [255:0] to_montgomery;
    input [255:0] a;
    input [255:0] N_val;
    input [255:0] R2_mod_N;
    
    reg [255:0] a_mont;
    reg [255:0] n_prime;
    begin
        n_prime = get_N_prime(N_val);
        a_mont = montgomery_multiply_ref(a, R2_mod_N, N_val, n_prime);
        to_montgomery = a_mont;
    end
endfunction

// 将蒙哥马利域数转换为普通数
function [255:0] from_montgomery;
    input [255:0] a_mont;
    input [255:0] N_val;
    
    reg [255:0] a;
    reg [255:0] n_prime;
    begin
        n_prime = get_N_prime(N_val);
        a = montgomery_multiply_ref(a_mont, 256'd1, N_val, n_prime);
        from_montgomery = a;
    end
endfunction

// 测试用例存储
reg [255:0] test_a_mont[0:9];
reg [255:0] test_b_mont[0:9];
reg [255:0] test_N[0:9];
reg [255:0] test_N_prime[0:9];
reg [255:0] test_expected[0:9];
integer num_tests = 0;
integer test_index = 0;
reg test_passed = 1;

// R2_mod_N 值
reg [255:0] R2_mod_N_5 = 256'h1;
reg [255:0] R2_mod_N_7 = 256'h4;
reg [255:0] R2_mod_N_11 = 256'h4;

// 测试状态机
reg [3:0] test_state;
localparam TEST_IDLE = 0;
localparam TEST_START = 1;
localparam TEST_WAIT = 2;
localparam TEST_CHECK = 3;
localparam TEST_DONE = 4;

// 初始化测试用例
task init_test_cases;
    begin
        // 测试用例1: 2 * 3 mod 5 = 1
        test_a_mont[0] = to_montgomery(256'd2, 256'd5, R2_mod_N_5);
        test_b_mont[0] = to_montgomery(256'd3, 256'd5, R2_mod_N_5);
        test_N[0] = 256'd5;
        test_N_prime[0] = get_N_prime(256'd5);
        test_expected[0] = to_montgomery(256'd1, 256'd5, R2_mod_N_5);
        
        // 测试用例2: 4 * 4 mod 5 = 1
        test_a_mont[1] = to_montgomery(256'd4, 256'd5, R2_mod_N_5);
        test_b_mont[1] = to_montgomery(256'd4, 256'd5, R2_mod_N_5);
        test_N[1] = 256'd5;
        test_N_prime[1] = get_N_prime(256'd5);
        test_expected[1] = to_montgomery(256'd1, 256'd5, R2_mod_N_5);
        
        // 测试用例3: 2 * 4 mod 7 = 1
        test_a_mont[2] = to_montgomery(256'd2, 256'd7, R2_mod_N_7);
        test_b_mont[2] = to_montgomery(256'd4, 256'd7, R2_mod_N_7);
        test_N[2] = 256'd7;
        test_N_prime[2] = get_N_prime(256'd7);
        test_expected[2] = to_montgomery(256'd1, 256'd7, R2_mod_N_7);
        
        // 测试用例4: 3 * 5 mod 11 = 4
        test_a_mont[3] = to_montgomery(256'd3, 256'd11, R2_mod_N_11);
        test_b_mont[3] = to_montgomery(256'd5, 256'd11, R2_mod_N_11);
        test_N[3] = 256'd11;
        test_N_prime[3] = get_N_prime(256'd11);
        test_expected[3] = to_montgomery(256'd4, 256'd11, R2_mod_N_11);
        
        // 测试用例5: 边界测试 a=0
        test_a_mont[4] = to_montgomery(256'd0, 256'd11, R2_mod_N_11);
        test_b_mont[4] = to_montgomery(256'd5, 256'd11, R2_mod_N_11);
        test_N[4] = 256'd11;
        test_N_prime[4] = get_N_prime(256'd11);
        test_expected[4] = to_montgomery(256'd0, 256'd11, R2_mod_N_11);
        
        // 测试用例6: 边界测试 a=1
        test_a_mont[5] = to_montgomery(256'd1, 256'd11, R2_mod_N_11);
        test_b_mont[5] = to_montgomery(256'd5, 256'd11, R2_mod_N_11);
        test_N[5] = 256'd11;
        test_N_prime[5] = get_N_prime(256'd11);
        test_expected[5] = to_montgomery(256'd5, 256'd11, R2_mod_N_11);
        
        // 测试用例7: 自乘测试
        test_a_mont[6] = to_montgomery(256'd3, 256'd7, R2_mod_N_7);
        test_b_mont[6] = to_montgomery(256'd3, 256'd7, R2_mod_N_7);
        test_N[6] = 256'd7;
        test_N_prime[6] = get_N_prime(256'd7);
        test_expected[6] = to_montgomery(256'd2, 256'd7, R2_mod_N_7);
        
        num_tests = 7;
    end
endtask

// 运行单个测试
task run_test;
    input integer index;
    begin
        // 设置测试输入
        a_mont = test_a_mont[index];
        b_mont = test_b_mont[index];
        N = test_N[index];
        N_prime = test_N_prime[index];
        
        // 启动测试
        start = 1;
        #10 start = 0;
        
        // 显示测试信息
        case (index)
            0: $display("[%t] Starting test 1: 2*3 mod 5", $time);
            1: $display("[%t] Starting test 2: 4*4 mod 5", $time);
            2: $display("[%t] Starting test 3: 2*4 mod 7", $time);
            3: $display("[%t] Starting test 4: 3*5 mod 11", $time);
            4: $display("[%t] Starting test 5: 0*5 mod 11", $time);
            5: $display("[%t] Starting test 6: 1*5 mod 11", $time);
            6: $display("[%t] Starting test 7: 3*3 mod 7", $time);
        endcase
        
        $display("  a_mont = %064h", a_mont);
        $display("  b_mont = %064h", b_mont);
        $display("  N = %064h", N);
        $display("  N_prime = %064h", N_prime);
        
        // 使用参考模型计算期望结果
        $display("  Expected result (Montgomery) = %064h", test_expected[index]);
        
        // 显示原始数字（转换回普通域）
        $display("  a = %d, b = %d, N = %d", 
                 from_montgomery(a_mont, N),
                 from_montgomery(b_mont, N),
                 N);
        $display("  Expected normal result = %d", 
                 from_montgomery(test_expected[index], N));
    end
endtask

// 检查测试结果
task check_test_result;
    input integer index;
    
    reg [255:0] expected;
    reg [255:0] actual;
    reg [255:0] ref_result;
    
    begin
        expected = test_expected[index];
        actual = result_mont;
        
        $display("[%t] Test %d complete", $time, index+1);
        $display("  Actual result = %064h", actual);
        $display("  Expected result = %064h", expected);
        $display("  Actual normal result = %d", from_montgomery(actual, N));
        
        if (actual === expected) begin
            $display("  ✓ Test PASSED");
        end else begin
            $display("  ✗ Test FAILED");
            test_passed = 0;
            
            // 显示详细信息
            $display("  Debug info:");
            $display("    a * b mod N in normal domain = %d * %d mod %d = %d", 
                     from_montgomery(a_mont, N),
                     from_montgomery(b_mont, N),
                     N,
                     from_montgomery(actual, N));
            
            // 计算参考模型结果进行对比
            ref_result = montgomery_multiply_ref(a_mont, b_mont, N, N_prime);
            $display("    Behavioral model result = %064h", ref_result);
            
            if (ref_result === expected) begin
                $display("    Behavioral model matches expected value");
            end else begin
                $display("    Behavioral model = %064h (differs from expected!)", ref_result);
            end
        end
        
        $display("");
    end
endtask

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
    test_state = TEST_IDLE;
    test_index = 0;
    test_passed = 1;
    
    // 初始化测试用例
    init_test_cases();
    
    // 复位
    #20 reset_n = 1;
    
    // 等待复位完成
    #50;
    
    // 开始测试
    test_state = TEST_START;
end

// 测试状态机
always @(posedge clk) begin
    case (test_state)
        TEST_START: begin
            if (test_index < num_tests) begin
                run_test(test_index);
                test_state = TEST_WAIT;
            end else begin
                test_state = TEST_DONE;
            end
        end
        
        TEST_WAIT: begin
            if (done) begin
                check_test_result(test_index);
                test_index = test_index + 1;
                
                // 等待几个周期再开始下一个测试
                #50;
                
                if (test_index < num_tests)
                    test_state = TEST_START;
                else
                    test_state = TEST_DONE;
            end
        end
        
        TEST_DONE: begin
            $display("\n=========================================");
            $display("Test Summary:");
            $display("Total tests: %0d", num_tests);
            if (test_passed) begin
                $display("All tests PASSED!");
            end else begin
                $display("Some tests FAILED!");
            end
            $display("=========================================\n");
            
            // 额外测试：直接测试蒙哥马利乘法
            $display("\nAdditional direct tests:");
            $display("=========================================");
            
            // 等待一段时间后开始额外测试
            #100;
            test_direct_multiplication();
            
            // 结束仿真
            #100;
            $finish;
        end
    endcase
end

// 直接测试蒙哥马利乘法（使用已知的蒙哥马利形式数字）
task test_direct_multiplication;
    reg [255:0] ref_result;
    begin
        $display("\nDirect test for N=5:");
        $display("Montgomery form of 2: %064h", to_montgomery(256'd2, 256'd5, R2_mod_N_5));
        $display("Montgomery form of 3: %064h", to_montgomery(256'd3, 256'd5, R2_mod_N_5));
        
        // 计算 2 * 3 * R^{-1} mod 5
        a_mont = to_montgomery(256'd2, 256'd5, R2_mod_N_5);
        b_mont = to_montgomery(256'd3, 256'd5, R2_mod_N_5);
        N = 256'd5;
        N_prime = get_N_prime(256'd5);
        
        // 使用行为级模型计算
        ref_result = montgomery_multiply_ref(a_mont, b_mont, N, N_prime);
        $display("Behavioral: mont_mul(2_mont, 3_mont) = %064h", ref_result);
        $display("Converted back: %d", from_montgomery(ref_result, N));
        
        // 使用DUT计算
        start = 1;
        #10 start = 0;
        
        // 等待完成
        wait(done);
        #10;
        
        $display("DUT: mont_mul(2_mont, 3_mont) = %064h", result_mont);
        $display("Converted back: %d", from_montgomery(result_mont, N));
        
        if (ref_result === result_mont) begin
            $display("✓ Direct test PASSED");
        end else begin
            $display("✗ Direct test FAILED");
        end
    end
endtask

// 监视器：记录关键信号变化
always @(posedge clk) begin
    if (start) begin
        $display("[%t] Multiplier started: a=%064h, b=%064h, N=%064h", 
                 $time, a_mont, b_mont, N);
    end
    
    if (done) begin
        $display("[%t] Multiplier done: result=%064h", $time, result_mont);
    end
end

endmodule