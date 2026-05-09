// test_winograd_simple.sv
`timescale 1ns/1ps

module test_winograd_simple;

// 参数
parameter WIDTH = 8;  // 使用8位测试
parameter CLK_PERIOD = 10;  // 100MHz时钟

// 信号
reg clk;
reg rst_n;
reg [1:0] radix_mode;
reg [WIDTH-1:0] core_result0 [0:7];
reg [WIDTH-1:0] core_result1 [0:7];
reg [7:0] core_done;
reg [WIDTH-1:0] conj_coeff [0:7];
reg [WIDTH-1:0] modulus;

wire [WIDTH-1:0] data_out [0:15];
wire result_valid;

// 时钟
initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

// 复位
initial begin
    rst_n = 0;
    #20;
    rst_n = 1;
end

// 被测模块
winograd_post_transform #(
    .MAX_WIDTH(WIDTH),
    .MAX_RADIX(16),
    .NUM_CORES(8)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .radix_mode(radix_mode),
    .core_result0(core_result0),
    .core_result1(core_result1),
    .core_done(core_done),
    .conj_coeff(conj_coeff),
    .modulus(modulus),
    .data_out(data_out),
    .result_valid(result_valid)
);
task initialize_all;
    begin
        // 重置所有输入
        radix_mode = 0;
        modulus = 0;
        core_done = 0;
        
        // 初始化所有数组元素
        for (int i = 0; i < 8; i++) begin
            core_result0[i] = 0;
            core_result1[i] = 0;
            conj_coeff[i] = 0;
        end
        
        // 等待一个周期
        @(posedge clk);
    end
endtask
// 主测试
initial begin
    // 初始化
    radix_mode = 0;
    modulus = 17;
    core_done = 0;
    
    // 初始化数组
    for (int i=0; i<8; i++) begin
        core_result0[i] = 0;
        core_result1[i] = 0;
        conj_coeff[i] = 0;
    end
    
    #50; // 等待复位完成
    
    $display("=== 开始测试 ===");
    
    // 测试1: 基2
    $display("\n测试1: 基2模式");
    initialize_all();
    radix_mode = 0;
    core_result0[0] = 5;
    core_result1[0] = 12;
    core_done = 8'b00000001;
    
    wait(result_valid);
    @(posedge clk);
    $display("data_out[0] = %d (期望: 5)", data_out[0]);
    $display("data_out[1] = %d (期望: 12)", data_out[1]);
    
    #20;
    core_done = 0;
    
    // 测试2: 基4
    $display("\n测试2: 基4模式");
    initialize_all();
    radix_mode = 1;
    core_result0[0] = 5;
    core_result0[1] = 8;
    core_result1[0] = 12;
    core_result1[1] = 3;
    core_done = 8'b00000011;
    
    wait(result_valid);
    @(posedge clk);
    $display("data_out[0] = %d (期望: 5)", data_out[0]);
    $display("data_out[1] = %d (期望: 8)", data_out[1]);
    $display("data_out[2] = %d (期望: 12)", data_out[2]);
    $display("data_out[3] = %d (期望: 3)", data_out[3]);
    
    #20;
    core_done = 0;
    
    // 测试3: 基8
    $display("\n测试3: 基8模式");
    initialize_all();
    radix_mode = 2;
    
    for (int i=0; i<4; i++) begin
        core_result0[i] = i+1;
        core_result1[i] = i+5;
    end
    
    core_done = 8'b00001111;
    
    wait(result_valid);
    @(posedge clk);
    for (int i=0; i<8; i++) begin
        $display("data_out[%d] = %d", i, data_out[i]);
    end
    
    #20;
    core_done = 0;
    
    // 结束
    #100;
    $display("\n=== 测试完成 ===");
    $finish;
end

// 监控输出
always @(posedge clk) begin
    if (result_valid) begin
        $display("[%0t] result_valid 信号置位", $time);
    end
end

endmodule