`timescale 1ns/1ps

module winograd_pre_transform_tb;
    // 参数定义
    parameter MAX_WIDTH = 8;      // 简化测试，使用8位宽度
    parameter MAX_RADIX = 16;
    parameter NUM_CORES = 8;
    
    // 时钟和复位信号
    reg clk;
    reg rst_n;
    reg start;
    
    // 配置信号
    reg [1:0] radix_mode;
    
    // 输入数据
    reg [MAX_WIDTH-1:0] data_in [0:MAX_RADIX-1];
    reg [MAX_WIDTH-1:0] twiddle_in [0:MAX_RADIX/2-1];
    reg [MAX_WIDTH-1:0] modulus;
    
    // 输出信号
    wire [MAX_WIDTH-1:0] x0_out [0:NUM_CORES-1];
    wire [MAX_WIDTH-1:0] x1_out [0:NUM_CORES-1];
    wire [MAX_WIDTH-1:0] w_out [0:NUM_CORES-1];
    wire [MAX_WIDTH-1:0] conj_coeff_out [0:NUM_CORES-1];
    wire valid_out;
    
    // 实例化被测试模块
    winograd_pre_transform #(
        .MAX_WIDTH(MAX_WIDTH),
        .MAX_RADIX(MAX_RADIX),
        .NUM_CORES(NUM_CORES)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .radix_mode(radix_mode),
        .data_in(data_in),
        .twiddle_in(twiddle_in),
        .modulus(modulus),
        .x0_out(x0_out),
        .x1_out(x1_out),
        .w_out(w_out),
        .conj_coeff_out(conj_coeff_out),
        .valid_out(valid_out)
    );
    
    // 生成时钟
    always #5 clk = ~clk;  // 100MHz时钟
    
    // 测试任务：初始化所有输入
    task init_inputs;
    begin
        start = 0;
        radix_mode = 0;
        modulus = 17;  // 使用质数17作为模数
        
        // 初始化数据输入
        for (integer i = 0; i < MAX_RADIX; i = i + 1) begin
            data_in[i] = i;  // 简单使用0-15作为输入
        end
        
        // 初始化旋转因子
        for (integer i = 0; i < MAX_RADIX/2; i = i + 1) begin
            twiddle_in[i] = (i + 1) % modulus;  // 简单旋转因子
        end
    end
    endtask
    
    // 测试任务：打印输出结果
    task print_outputs;
    input integer test_num;
    begin
        $display("=== Test %0d Outputs ===", test_num);
        $display("Valid: %b", valid_out);
        
        for (integer i = 0; i < NUM_CORES; i = i + 1) begin
            if (x0_out[i] != 0 || x1_out[i] != 0 || w_out[i] != 0 || conj_coeff_out[i] != 0) begin
                $display("Core %0d: x0=%h, x1=%h, w=%h, conj=%h", 
                         i, x0_out[i], x1_out[i], w_out[i], conj_coeff_out[i]);
            end
        end
        $display("");
    end
    endtask
    
    // 测试任务：执行一次变换
    task run_test;
    input [1:0] mode;
    input string mode_name;
    begin
        $display("\n=== Testing %s Mode ===", mode_name);
        
        // 设置模式
        radix_mode = mode;
        
        // 启动变换
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;
        
        // 等待变换完成
        wait(valid_out == 1);
        @(posedge clk);
        
        // 打印结果
        print_outputs(mode + 1);
        
        // 等待valid信号变低
        @(posedge clk);
        wait(valid_out == 0);
        @(posedge clk);
    end
    endtask
    
    // 主测试流程
    initial begin
        // 初始化
        clk = 0;
        rst_n = 0;
        init_inputs();
        
        // 复位
        #10 rst_n = 1;
        #10;
        
        $display("====================================");
        $display("Winograd Pre-Transform Testbench");
        $display("Modulus: %0d", modulus);
        $display("====================================");
        
        // 测试基2模式
        run_test(2'b00, "Radix-2");
        
        // 测试基4模式
        run_test(2'b01, "Radix-4");
        
        // 测试基8模式
        run_test(2'b10, "Radix-8");
        
        // 测试基16模式
        run_test(2'b11, "Radix-16");
        
        // 额外测试：测试模块空闲状态
        $display("=== Testing Idle State ===");
        #100;
        
        // 验证复位后的状态
        $display("=== Testing Reset ===");
        rst_n = 0;
        #10;
        rst_n = 1;
        #10;
        
        // 检查所有输出是否被清零
        for (integer i = 0; i < NUM_CORES; i = i + 1) begin
            if (x0_out[i] !== 0 || x1_out[i] !== 0 || w_out[i] !== 0 || conj_coeff_out[i] !== 0) begin
                $display("ERROR: Outputs not cleared after reset!");
                $finish;
            end
        end
        
        $display("=== All Tests Completed Successfully ===");
        $display("====================================");
        
        #100;
        $finish;
    end
    
    // 监视信号变化
    initial begin
        // 监视重要信号
        $monitor("Time=%0t: state=%d, valid=%b, radix_mode=%b", 
                 $time, dut.state, valid_out, radix_mode);
    end
    
    // 生成波形文件
    initial begin
        $dumpfile("winograd_pre_transform.vcd");
        $dumpvars(0, winograd_pre_transform_tb);
    end
    
endmodule