`timescale 1ns/1ps

module tb_ntt_accelerator;

    // 参数定义（和IP内部固化参数严格一致）
    parameter MAX_WIDTH   = 128;
    parameter MAX_RADIX   = 16;
    parameter NUM_CORES   = 4;
    parameter CLK_PERIOD  = 10;
    parameter PIPELINE_WAIT_CYCLE = 120;
    
    // 时钟和复位
    reg clk;
    reg rst_n;
    
    // IP 展平扁平总线端口
    reg [1:0] radix_mode;
    reg width_384_mode;
    reg [2:0] parallelism;
    reg start;
    wire done;
    wire result_valid;

    reg  [MAX_WIDTH*MAX_RADIX - 1 : 0] data_in_flat;
    reg  [MAX_WIDTH*(MAX_RADIX/2) - 1 : 0] twiddle_flat;

    reg [MAX_WIDTH-1:0] modulus;
    reg [MAX_WIDTH-1:0] N_prime;
    reg [MAX_WIDTH-1:0] R2_mod_N;

    wire [MAX_WIDTH*MAX_RADIX - 1 : 0] data_out_flat;

    // 例化你打包好的自定义 IP（名字完全按你现在的）
    NTT_accelerator_0 dut (
        .clk(clk),
        .rst_n(rst_n),
        .radix_mode(radix_mode),
        .width_384_mode(width_384_mode),
        .parallelism(parallelism),
        .start(start),
        .done(done),
        .result_valid(result_valid),
        .data_in(data_in_flat),
        .twiddle_factors(twiddle_flat),
        .modulus(modulus),
        .N_prime(N_prime),
        .R2_mod_N(R2_mod_N),
        .data_out(data_out_flat)
    );

    // 扁平总线 → 数组拆分（ Vivado 官方映射）
    wire [MAX_WIDTH-1:0] data_out [0:MAX_RADIX-1];

    assign data_out[0]  = data_out_flat[127:0];
    assign data_out[1]  = data_out_flat[255:128];
    assign data_out[2]  = data_out_flat[383:256];
    assign data_out[3]  = data_out_flat[511:384];
    assign data_out[4]  = data_out_flat[639:512];
    assign data_out[5]  = data_out_flat[767:640];
    assign data_out[6]  = data_out_flat[895:768];
    assign data_out[7]  = data_out_flat[1023:896];
    assign data_out[8]  = data_out_flat[1151:1024];
    assign data_out[9]  = data_out_flat[1279:1152];
    assign data_out[10] = data_out_flat[1407:1280];
    assign data_out[11] = data_out_flat[1535:1408];
    assign data_out[12] = data_out_flat[1663:1536];
    assign data_out[13] = data_out_flat[1791:1664];
    assign data_out[14] = data_out_flat[1919:1792];
    assign data_out[15] = data_out_flat[2047:1920];

    // 时钟生成
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // 主测试流程
    initial begin
        initialize();
        #(CLK_PERIOD*5);
        
        test_radix_2();
        #(CLK_PERIOD*PIPELINE_WAIT_CYCLE);
        
        test_radix_4();
        #(CLK_PERIOD*PIPELINE_WAIT_CYCLE);
        
        test_radix_8();
        #(CLK_PERIOD*PIPELINE_WAIT_CYCLE);
        
        test_radix_16();
        
        #(CLK_PERIOD*50);
        $display("\n所有模式测试全部完成!");
        $finish;
    end
    
    // 初始化
    task initialize;
        integer i;
    begin
        rst_n = 0;
        start = 0;
        radix_mode = 0;
        width_384_mode = 0;
        parallelism = 0;
        
        modulus   = 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF61;
        N_prime   = 128'h9D8F6A3C5E7B2D4F1A0E8C6B5D7F3A2C;
        R2_mod_N  = 128'h123456789ABCDEF0FEDCBA9876543210;
        
        data_in_flat = '0;
        twiddle_flat = '0;
        
        #(CLK_PERIOD*2);
        rst_n = 1;
    end
    endtask

    // 模式清空
    task mode_clear;
    begin
        start = 1'b0;
        data_in_flat = '0;
        twiddle_flat = '0;
        #(CLK_PERIOD*10);
    end
    endtask
    
    // 基2模式
    task test_radix_2;
        integer i;
    begin
        $display("\n==========================================");
        $display("开始测试: 基2模式");
        $display("==========================================");
        mode_clear();
        
        radix_mode = 2'b00;
        parallelism = 3'b000;
        
        data_in_flat[127:0]    = 128'h123456789ABCDEF0FEDCBA9876543210;
        data_in_flat[255:128]  = 128'hFEDCBA9876543210123456789ABCDEF0;
        twiddle_flat[127:0]    = 128'h9D8F6A3C5E7B2D4F1A0E8C6B5D7F3A2C;
        
        $display("启动计算...");
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;
        
        wait(done == 1'b1);
        $display("基2模式计算完成!");
        
        $display("输出结果:");
        for (i = 0; i < 2; i = i + 1) begin
            $display("  data_out[%0d] = %h", i, data_out[i]);
        end
    end
    endtask
    
    // 基4模式
    task test_radix_4;
        integer i;
    begin
        $display("\n==========================================");
        $display("开始测试: 基4模式");
        $display("==========================================");
        mode_clear();
        
        radix_mode = 2'b01;
        parallelism = 3'b001;
        
        data_in_flat[127:0]    = 128'h11111111111111111111111111111111;
        data_in_flat[255:128]  = 128'h22222222222222222222222222222222;
        data_in_flat[383:256]  = 128'h33333333333333333333333333333333;
        data_in_flat[511:384]  = 128'h44444444444444444444444444444444;
        
        twiddle_flat[127:0]    = 128'hAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA;
        twiddle_flat[255:128]  = 128'hBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB;
        
        $display("启动计算...");
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;
        
        wait(done == 1'b1);
        $display("基4模式计算完成!");
        
        $display("输出结果:");
        for (i = 0; i < 4; i = i + 1) begin
            $display("  data_out[%0d] = %h", i, data_out[i]);
        end
    end
    endtask
    
    // 基8模式
    task test_radix_8;
        integer i;
    begin
        $display("\n==========================================");
        $display("开始测试: 基8模式");
        $display("==========================================");
        mode_clear();
        
        radix_mode = 2'b10;
        parallelism = 3'b010;
        
        data_in_flat[127:0]    = {64'h0000000000000000, 64'h0000000000000001};
        data_in_flat[255:128]  = {64'h0000000000000000, 64'h0000000000000001};
        data_in_flat[383:256]  = {64'h0000000000000000, 64'h0000000000000001};
        data_in_flat[511:384]  = {64'h0000000000000000, 64'h0000000000000001};
        data_in_flat[639:512]  = {64'h0000000000000000, 64'h0000000000000001};
        data_in_flat[767:640]  = {64'h0000000000000000, 64'h0000000000000001};
        data_in_flat[895:768]  = {64'h0000000000000000, 64'h0000000000000001};
        data_in_flat[1023:896] = {64'h0000000000000000, 64'h0000000000000001};

        twiddle_flat[127:0]    = {64'h0000000000000000, 64'h0000000000000002};
        twiddle_flat[255:128]  = {64'h0000000000000000, 64'h0000000000000002};
        twiddle_flat[383:256]  = {64'h0000000000000000, 64'h0000000000000002};
        twiddle_flat[511:384]  = {64'h0000000000000000, 64'h0000000000000002};
        
        $display("启动计算...");
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;
        
        wait(done == 1'b1);
        $display("基8模式计算完成!");
        
        $display("输出结果:");
        for (i = 0; i < 8; i = i + 1) begin
            $display("  data_out[%0d] = %h", i, data_out[i]);
        end
    end
    endtask
    
    // 基16模式
    task test_radix_16;
        integer i;
    begin
        $display("\n==========================================");
        $display("开始测试: 基16模式");
        $display("==========================================");
        mode_clear();
        
        radix_mode = 2'b11;
        parallelism = 3'b010;
        
        data_in_flat[127:0]    = {64'h0000000000000000, 64'h0000000000000003};
        data_in_flat[255:128]  = {64'h0000000000000000, 64'h0000000000000003};
        data_in_flat[383:256]  = {64'h0000000000000000, 64'h0000000000000003};
        data_in_flat[511:384]  = {64'h0000000000000000, 64'h0000000000000003};
        data_in_flat[639:512]  = {64'h0000000000000000, 64'h0000000000000003};
        data_in_flat[767:640]  = {64'h0000000000000000, 64'h0000000000000003};
        data_in_flat[895:768]  = {64'h0000000000000000, 64'h0000000000000003};
        data_in_flat[1023:896] = {64'h0000000000000000, 64'h0000000000000003};
        data_in_flat[1151:1024]= {64'h0000000000000000, 64'h0000000000000003};
        data_in_flat[1279:1152]= {64'h0000000000000000, 64'h0000000000000003};
        data_in_flat[1407:1280]= {64'h0000000000000000, 64'h0000000000000003};
        data_in_flat[1535:1408]= {64'h0000000000000000, 64'h0000000000000003};
        data_in_flat[1663:1536]= {64'h0000000000000000, 64'h0000000000000003};
        data_in_flat[1791:1664]= {64'h0000000000000000, 64'h0000000000000003};
        data_in_flat[1919:1792]= {64'h0000000000000000, 64'h0000000000000003};
        data_in_flat[2047:1920]= {64'h0000000000000000, 64'h0000000000000003};

        twiddle_flat[127:0]    = {64'h0000000000000000, 64'h0000000000000004};
        twiddle_flat[255:128]  = {64'h0000000000000000, 64'h0000000000000004};
        twiddle_flat[383:256]  = {64'h0000000000000000, 64'h0000000000000004};
        twiddle_flat[511:384]  = {64'h0000000000000000, 64'h0000000000000004};
        twiddle_flat[639:512]  = {64'h0000000000000000, 64'h0000000000000004};
        twiddle_flat[767:640]  = {64'h0000000000000000, 64'h0000000000000004};
        twiddle_flat[895:768]  = {64'h0000000000000000, 64'h0000000000000004};
        twiddle_flat[1023:896] = {64'h0000000000000000, 64'h0000000000000004};
        
        $display("启动计算...");
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;
        
        wait(done == 1'b1);
        $display("基16模式计算完成!");
        
        $display("输出结果:");
        for (i = 0; i < 16; i = i + 1) begin
            $display("  data_out[%0d] = %h", i, data_out[i]);
        end
    end
    endtask
    
    // 时序监控
    initial begin
        $monitor("Time=%0t: start=%b, done=%b, result_valid=%b", 
                 $time, start, done, result_valid);
    end
    
endmodule