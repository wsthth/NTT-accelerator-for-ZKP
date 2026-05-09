module winograd_post_transform_tb;
    parameter MAX_WIDTH = 8;
    parameter MAX_RADIX = 16;
    parameter NUM_CORES = 8;
    
    reg clk, rst_n;
    reg [1:0] radix_mode;
    reg [MAX_WIDTH-1:0] core_result0 [0:NUM_CORES-1];
    reg [MAX_WIDTH-1:0] core_result1 [0:NUM_CORES-1];
    reg [NUM_CORES-1:0] core_done;
    reg [MAX_WIDTH-1:0] conj_coeff [0:NUM_CORES-1];
    reg [MAX_WIDTH-1:0] modulus;
    
    wire [MAX_WIDTH-1:0] data_out [0:MAX_RADIX-1];
    wire result_valid;
    
    // 实例化
    winograd_post_transform #(
        .MAX_WIDTH(MAX_WIDTH),
        .MAX_RADIX(MAX_RADIX),
        .NUM_CORES(NUM_CORES)
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
    
    // 时钟生成
    always #5 clk = ~clk;
    
    initial begin
        clk = 0;
        rst_n = 0;
        modulus = 17;  // 使用小模数便于测试
        
        #20 rst_n = 1;
        
        // 测试基16模式
        radix_mode = 2'b11;
        core_done = 8'b11111111;  // 所有子核完成
        
        // 设置测试数据
        for (integer i = 0; i < NUM_CORES; i = i + 1) begin
            core_result0[i] = i;
            core_result1[i] = i + 8;
            conj_coeff[i] = (i + 1) % modulus;
        end
        
        #100;
        
        // 检查输出
        for (integer i = 0; i < MAX_RADIX; i = i + 1) begin
            $display("data_out[%0d] = %h", i, data_out[i]);
        end
        
        #100 $finish;
    end
endmodule