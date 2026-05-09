`timescale 1ns/1ps

module reconfigurable_3d_pe_top_tb;

    // 参数定义
    parameter MAX_WIDTH = 128;
    parameter MAX_RADIX = 16;
    parameter NUM_CORES = 4;
    
    // 时钟和复位
    reg clk;
    reg rst_n;
    parameter CLK_PERIOD = 10;
    
    // DUT接口
    reg [1:0] radix_mode;
    reg width_384_mode;
    reg [2:0] parallelism;
    reg start;
    wire done;
    wire result_valid;
    
    // 数据输入数组
    reg [MAX_WIDTH-1:0] data_in [0:MAX_RADIX-1];
    reg [MAX_WIDTH-1:0] twiddle_factors [0:MAX_RADIX/2-1];
    reg [MAX_WIDTH-1:0] modulus;
    reg [MAX_WIDTH-1:0] N_prime;
    reg [MAX_WIDTH-1:0] R2_mod_N;
    
    // 数据输出数组
    wire [MAX_WIDTH-1:0] data_out [0:MAX_RADIX-1];
    
    // 实例化DUT
    reconfigurable_3d_pe_top #(
        .MAX_WIDTH(MAX_WIDTH),
        .MAX_RADIX(MAX_RADIX),
        .NUM_CORES(NUM_CORES)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .radix_mode(radix_mode),
        .width_384_mode(width_384_mode),
        .parallelism(parallelism),
        .start(start),
        .done(done),
        .result_valid(result_valid),
        .data_in(data_in),
        .twiddle_factors(twiddle_factors),
        .modulus(modulus),
        .N_prime(N_prime),
        .R2_mod_N(R2_mod_N),
        .data_out(data_out)
    );
    
    // 时钟生成
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // 主测试程序
    initial begin
        // 初始化
        initialize();
        
        // 等待复位完成
        #(CLK_PERIOD*5);
        
        // 测试1: 基2模式
        test_radix_2();
        
        // 等待一段时间
        #(CLK_PERIOD*20);
        
        // 测试2: 基4模式
        test_radix_4();
        
        // 等待一段时间
        #(CLK_PERIOD*20);
        
        // 测试3: 基8模式
        test_radix_8();
        
        // 等待一段时间
        #(CLK_PERIOD*20);
        
        // 测试4: 基16模式
        test_radix_16();
        
        // 结束仿真
        #(CLK_PERIOD*50);
        $display("\n所有测试完成!");
        $finish;
    end
    
    // 初始化任务
    task initialize;
        integer i;
    begin
        // 复位系统
        rst_n = 0;
        start = 0;
        radix_mode = 0;
        width_384_mode = 0;
        parallelism = 0;
        
        // 初始化模运算参数
        modulus = 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF61;
        N_prime = 128'h9D8F6A3C5E7B2D4F1A0E8C6B5D7F3A2C;
        R2_mod_N = 128'h123456789ABCDEF0FEDCBA9876543210;
        
        // 初始化数据数组
        for (i = 0; i < MAX_RADIX; i = i + 1) begin
            data_in[i] = 128'h0;
        end
        
        for (i = 0; i < MAX_RADIX/2; i = i + 1) begin
            twiddle_factors[i] = 128'h0;
        end
        
        // 释放复位
        #(CLK_PERIOD*2);
        rst_n = 1;
    end
    endtask
    
    // 基2模式测试
    task test_radix_2;
        integer i;
    begin
        $display("\n==========================================");
        $display("开始测试: 基2模式");
        $display("==========================================");
        
        // 配置参数
        radix_mode = 2'b00;    // 基2
        parallelism = 3'b000;  // 并行度1
        
        // 初始化输入数据（基2需要2个输入）
        data_in[0] = 128'h123456789ABCDEF0FEDCBA9876543210;
        data_in[1] = 128'hFEDCBA9876543210123456789ABCDEF0;
        
        // 初始化旋转因子（基2需要1个）
        twiddle_factors[0] = 128'h9D8F6A3C5E7B2D4F1A0E8C6B5D7F3A2C;
        
        // 启动计算
        $display("启动计算...");
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;
        
        // 等待计算完成
        wait(done == 1'b1);
        $display("计算完成!");
        
        // 显示输出结果
        $display("输出结果:");
        for (i = 0; i < 2; i = i + 1) begin
            $display("  data_out[%0d] = %h", i, data_out[i]);
        end
        
        // 简单验证
        $display("测试完成: 基2模式");
    end
    endtask
    
    // 基4模式测试
    task test_radix_4;
        integer i;
    begin
        $display("\n==========================================");
        $display("开始测试: 基4模式");
        $display("==========================================");
        
        // 配置参数
        radix_mode = 2'b01;    // 基4
        parallelism = 3'b001;  // 并行度2
        
        // 初始化输入数据（基4需要4个输入）
        data_in[0] = 128'h11111111111111111111111111111111;
        data_in[1] = 128'h22222222222222222222222222222222;
        data_in[2] = 128'h33333333333333333333333333333333;
        data_in[3] = 128'h44444444444444444444444444444444;
        
        // 初始化旋转因子（基4需要2个）
        twiddle_factors[0] = 128'hAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA;
        twiddle_factors[1] = 128'hBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB;
        
        // 启动计算
        $display("启动计算...");
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;
        
        // 等待计算完成
        wait(done == 1'b1);
        $display("计算完成!");
        
        // 显示输出结果
        $display("输出结果:");
        for (i = 0; i < 4; i = i + 1) begin
            $display("  data_out[%0d] = %h", i, data_out[i]);
        end
        
        $display("测试完成: 基4模式");
    end
    endtask
    
    // 基8模式测试
    task test_radix_8;
        integer i;
    begin
        $display("\n==========================================");
        $display("开始测试: 基8模式");
        $display("==========================================");
        
        // 配置参数
        radix_mode = 2'b10;    // 基8
        parallelism = 3'b010;  // 并行度4
        
        // 初始化输入数据（基8需要8个输入）
        for (i = 0; i < 8; i = i + 1) begin
            data_in[i] = {64'h0000000000000000, 64'h0000000000000001};
        end
        
        // 初始化旋转因子（基8需要4个）
        for (i = 0; i < 4; i = i + 1) begin
            twiddle_factors[i] = {64'h0000000000000000, 64'h0000000000000002};
        end
        
        // 启动计算
        $display("启动计算...");
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;
        
        // 等待计算完成
        wait(done == 1'b1);
        $display("计算完成!");
        
        // 显示输出结果
        $display("输出结果:");
        for (i = 0; i < 8; i = i + 1) begin
            $display("  data_out[%0d] = %h", i, data_out[i]);
        end
        
        $display("测试完成: 基8模式");
    end
    endtask
    
    // 基16模式测试
    task test_radix_16;
        integer i;
    begin
        $display("\n==========================================");
        $display("开始测试: 基16模式");
        $display("==========================================");
        
        // 配置参数
        radix_mode = 2'b11;    // 基16
        parallelism = 3'b010;  // 并行度4
        
        // 初始化输入数据（基16需要16个输入）
        for (i = 0; i < 16; i = i + 1) begin
            data_in[i] = {64'h0000000000000000, 64'h0000000000000003};
        end
        
        // 初始化旋转因子（基16需要8个）
        for (i = 0; i < 8; i = i + 1) begin
            twiddle_factors[i] = {64'h0000000000000000, 64'h0000000000000004};
        end
        
        // 启动计算
        $display("启动计算...");
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;
        
        // 等待计算完成
        wait(done == 1'b1);
        $display("计算完成!");
        
        // 显示输出结果
        $display("输出结果:");
        for (i = 0; i < 16; i = i + 1) begin
            $display("  data_out[%0d] = %h", i, data_out[i]);
        end
        
        $display("测试完成: 基16模式");
    end
    endtask
    
    // 监控信号变化
    initial begin
        $monitor("Time=%0t: start=%b, done=%b, result_valid=%b", 
                 $time, start, done, result_valid);
    end
    
    // 生成波形文件
    initial begin
        $dumpfile("reconfigurable_3d_pe_top_tb.vcd");
        $dumpvars(0, reconfigurable_3d_pe_top_tb);
    end
    
endmodule