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
        for (int i = 0; i < MAX_RADIX; i++) begin
            data_in[i] = 128'h0;
        end
        
        for (int i = 0; i < MAX_RADIX/2; i++) begin
            twiddle_factors[i] = 128'h0;
        end
        
        // 等待复位
        #(CLK_PERIOD*5);
        rst_n = 1;
        #(CLK_PERIOD*5);
        
        $display("==========================================");
        $display("开始测试: 基2模式");
        $display("==========================================");
        
        // 测试基2模式
        radix_mode = 2'b00;    // 基2
        parallelism = 3'b000;  // 并行度1
        
        // 设置简单的测试数据
        data_in[0] = 128'h00000000000000000000000000000001;
        data_in[1] = 128'h00000000000000000000000000000002;
        twiddle_factors[0] = 128'h00000000000000000000000000000003;
        
        // 启动计算
        $display("启动计算...");
        start = 1;
        #(CLK_PERIOD);
        start = 0;
        
        // 等待done信号
        wait(done == 1'b1);
        $display("计算完成!");
        
        // 显示输出
        $display("输出结果:");
        for (int i = 0; i < 2; i++) begin
            $display("  data_out[%0d] = %h", i, data_out[i]);
        end
        
        // 检查result_valid信号
        if (result_valid == 1'b1) begin
            $display("? result_valid信号正确");
        end else begin
            $display("? result_valid信号错误");
        end
        
        // 等待一段时间
        #(CLK_PERIOD*20);
        
        $display("\n测试完成!");
        $finish;
    end
    
    // 超时检测
    initial begin
        #(CLK_PERIOD*1000);  // 1000个时钟周期后超时
        $display("\n错误: 仿真超时!");
        $display("当前状态: start=%b, done=%b, result_valid=%b", start, done, result_valid);
        $finish;
    end
    
    // 监控信号变化
    always @(posedge clk) begin
        if (start) begin
            $display("Time=%0t: start信号拉高", $time);
        end
        
        if (done) begin
            $display("Time=%0t: done信号拉高", $time);
        end
        
        if (result_valid) begin
            $display("Time=%0t: result_valid信号拉高", $time);
        end
    end
    
    // 生成波形文件
    initial begin
        $dumpfile("reconfigurable_3d_pe_top_tb.vcd");
        $dumpvars(0, reconfigurable_3d_pe_top_tb);
        $dumpvars(1, dut);  // 添加DUT内部信号
    end
    
endmodule