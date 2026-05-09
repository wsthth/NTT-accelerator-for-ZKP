// ============================================================================
// 文件名: simple_64bit_subcore.v
// 描述: 简化版64位子核，处理64位分段数据
// 输入: 64位分段数据，进行模乘和加减运算
// 输出: 64位结果，供上层拼接为256位
// ============================================================================
module simple_64bit_subcore #(
    parameter DATA_WIDTH = 64,
    parameter MODULUS = 64'hFFFFFFFF00000001  // 默认模数
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // 控制信号
    input wire start,        // 开始计算
    input wire add_mode,     // 0:减法, 1:加法
    output reg done,         // 计算完成
    output reg busy,         // 忙碌状态
    
    // 数据输入
    input wire [DATA_WIDTH-1:0] x0_i,    // x0的第i个64位分段
    input wire [DATA_WIDTH-1:0] x1_i,    // x1的第i个64位分段
    input wire [DATA_WIDTH-1:0] w_i,     // w的第i个64位分段
    input wire [DATA_WIDTH-1:0] modulus, // 模数
    
    // 结果输出
    output reg [DATA_WIDTH-1:0] result,  // 64位结果
    output reg result_valid               // 结果有效
);

// ============================================================================
// 状态机定义
// ============================================================================
localparam [2:0]
    STATE_IDLE   = 3'b000,
    STATE_MUL    = 3'b001,  // 乘法阶段
    STATE_MOD    = 3'b010,  // 模约简阶段
    STATE_ADDSUB = 3'b011,  // 加减法阶段
    STATE_DONE   = 3'b100;
    
reg [2:0] current_state, next_state;

// ============================================================================
// 数据寄存器
// ============================================================================
reg [DATA_WIDTH-1:0] x0_reg, x1_reg, w_reg, mod_reg;
reg [2*DATA_WIDTH-1:0] product;  // 128位乘积
reg [DATA_WIDTH-1:0] product_mod; // 模约简后的乘积
reg [DATA_WIDTH-1:0] final_result; // 最终结果

// ============================================================================
// 计数器
// ============================================================================
reg [3:0] cycle_counter;

// ============================================================================
// 状态机主逻辑
// ============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        current_state <= STATE_IDLE;
        done <= 1'b0;
        busy <= 1'b0;
        result_valid <= 1'b0;
        
        // 复位寄存器
        x0_reg <= {DATA_WIDTH{1'b0}};
        x1_reg <= {DATA_WIDTH{1'b0}};
        w_reg <= {DATA_WIDTH{1'b0}};
        mod_reg <= MODULUS;
        product <= {2*DATA_WIDTH{1'b0}};
        product_mod <= {DATA_WIDTH{1'b0}};
        final_result <= {DATA_WIDTH{1'b0}};
        result <= {DATA_WIDTH{1'b0}};
        cycle_counter <= 4'd0;
    end else begin
        current_state <= next_state;
        
        case (current_state)
            STATE_IDLE: begin
                done <= 1'b0;
                busy <= 1'b0;
                result_valid <= 1'b0;
                cycle_counter <= 4'd0;
                
                if (start) begin
                    // 锁存输入数据
                    x0_reg <= x0_i;
                    x1_reg <= x1_i;
                    w_reg <= w_i;
                    mod_reg <= modulus;
                    busy <= 1'b1;
                    next_state <= STATE_MUL;
                end else begin
                    next_state <= STATE_IDLE;
                end
            end
            
            STATE_MUL: begin
                // 64位乘法: product = x1_i * w_i
                product <= x1_reg * w_reg;
                cycle_counter <= cycle_counter + 1;
                next_state <= STATE_MOD;
            end
            
            STATE_MOD: begin
                // 简单的模约简: product_mod = product % modulus
                // 注意: 实际应用中应该使用蒙哥马利约简
                product_mod <= product % mod_reg;
                cycle_counter <= cycle_counter + 1;
                next_state <= STATE_ADDSUB;
            end
            
            STATE_ADDSUB: begin
                if (add_mode) begin
                    // 加法模式: final_result = (x0_i + product_mod) % modulus
                    final_result <= (x0_reg + product_mod) % mod_reg;
                end else begin
                    // 减法模式: final_result = (x0_i - product_mod + modulus) % modulus
                    if (x0_reg >= product_mod) begin
                        final_result <= (x0_reg - product_mod) % mod_reg;
                    end else begin
                        final_result <= (x0_reg + mod_reg - product_mod) % mod_reg;
                    end
                end
                cycle_counter <= cycle_counter + 1;
                next_state <= STATE_DONE;
            end
            
            STATE_DONE: begin
                // 输出结果
                result <= final_result;
                result_valid <= 1'b1;
                done <= 1'b1;
                busy <= 1'b0;
                
                if (!start) begin
                    next_state <= STATE_IDLE;
                    result_valid <= 1'b0;
                end else begin
                    next_state <= STATE_DONE;
                end
            end
            
            default: begin
                next_state <= STATE_IDLE;
            end
        endcase
    end
end

endmodule

// ============================================================================
// 文件名: top_256bit_processor.v
// 描述: 顶层模块，将256位数据拆分为4个64位分段，使用4个子核并行处理
// ============================================================================
module top_256bit_processor #(
    parameter TOTAL_WIDTH = 256,
    parameter SEG_WIDTH = 64,
    parameter SEG_COUNT = TOTAL_WIDTH / SEG_WIDTH
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // 控制信号
    input wire start,        // 开始计算
    input wire add_mode,     // 0:减法, 1:加法
    output wire done,        // 计算完成
    
    // 256位数据输入
    input wire [TOTAL_WIDTH-1:0] x0,  // 完整256位x0
    input wire [TOTAL_WIDTH-1:0] x1,  // 完整256位x1
    input wire [TOTAL_WIDTH-1:0] w,   // 完整256位w
    input wire [TOTAL_WIDTH-1:0] modulus, // 256位模数
    
    // 256位结果输出
    output wire [TOTAL_WIDTH-1:0] result,  // 256位结果
    output wire result_valid                // 结果有效
);

// ============================================================================
// 拆分256位数据为4个64位分段
// ============================================================================
wire [SEG_WIDTH-1:0] x0_segments [0:SEG_COUNT-1];
wire [SEG_WIDTH-1:0] x1_segments [0:SEG_COUNT-1];
wire [SEG_WIDTH-1:0] w_segments [0:SEG_COUNT-1];
wire [SEG_WIDTH-1:0] mod_segments [0:SEG_COUNT-1];

// 分配分段
assign x0_segments[0] = x0[63:0];
assign x0_segments[1] = x0[127:64];
assign x0_segments[2] = x0[191:128];
assign x0_segments[3] = x0[255:192];

assign x1_segments[0] = x1[63:0];
assign x1_segments[1] = x1[127:64];
assign x1_segments[2] = x1[191:128];
assign x1_segments[3] = x1[255:192];

assign w_segments[0] = w[63:0];
assign w_segments[1] = w[127:64];
assign w_segments[2] = w[191:128];
assign w_segments[3] = w[255:192];

// 模数也拆分（实际处理时每个子核使用完整的64位模数）
// 注意：这里假设模数的低64位足够，实际应用可能需要更复杂的处理
assign mod_segments[0] = modulus[63:0];
assign mod_segments[1] = modulus[63:0];
assign mod_segments[2] = modulus[63:0];
assign mod_segments[3] = modulus[63:0];

// ============================================================================
// 4个64位子核实例
// ============================================================================
wire [SEG_WIDTH-1:0] subcore_results [0:SEG_COUNT-1];
wire subcore_done [0:SEG_COUNT-1];
wire subcore_busy [0:SEG_COUNT-1];
wire subcore_valid [0:SEG_COUNT-1];

genvar i;
generate
    for (i = 0; i < SEG_COUNT; i = i + 1) begin : gen_subcores
        simple_64bit_subcore #(
            .DATA_WIDTH(SEG_WIDTH),
            .MODULUS(64'hFFFFFFFF00000001)
        ) u_subcore (
            .clk(clk),
            .rst_n(rst_n),
            .start(start),
            .add_mode(add_mode),
            .done(subcore_done[i]),
            .busy(subcore_busy[i]),
            
            .x0_i(x0_segments[i]),
            .x1_i(x1_segments[i]),
            .w_i(w_segments[i]),
            .modulus(mod_segments[i]),
            
            .result(subcore_results[i]),
            .result_valid(subcore_valid[i])
        );
    end
endgenerate

// ============================================================================
// 拼接4个64位结果为256位
// ============================================================================
reg [TOTAL_WIDTH-1:0] final_result_reg;
reg final_valid_reg;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        final_result_reg <= {TOTAL_WIDTH{1'b0}};
        final_valid_reg <= 1'b0;
    end else if (&subcore_valid) begin  // 所有子核都输出有效结果
        // 拼接结果: [分段3][分段2][分段1][分段0]
        final_result_reg <= {
            subcore_results[3],
            subcore_results[2], 
            subcore_results[1],
            subcore_results[0]
        };
        final_valid_reg <= 1'b1;
    end else begin
        final_valid_reg <= 1'b0;
    end
end

// ============================================================================
// 输出信号
// ============================================================================
assign done = &subcore_done;  // 所有子核都完成
assign result = final_result_reg;
assign result_valid = final_valid_reg;

// ============================================================================
// 性能监控（可选）
// ============================================================================
reg [7:0] latency_counter;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        latency_counter <= 8'd0;
    end else if (start) begin
        latency_counter <= 8'd1;
    end else if (busy) begin
        latency_counter <= latency_counter + 8'd1;
    end else if (done) begin
        // 保持计数值直到下次开始
    end
end

endmodule

// ============================================================================
// 文件名: testbench_simple_subcore.v
// 描述: 测试平台，验证64位子核和256位处理器
// ============================================================================
module testbench_simple_subcore;

// 参数定义
parameter CLK_PERIOD = 10;
parameter SEG_WIDTH = 64;
parameter TOTAL_WIDTH = 256;

// 信号定义
reg clk;
reg rst_n;
reg start;
reg add_mode;
wire done;
wire [TOTAL_WIDTH-1:0] result;
wire result_valid;

// 测试数据
reg [TOTAL_WIDTH-1:0] x0_test;
reg [TOTAL_WIDTH-1:0] x1_test;
reg [TOTAL_WIDTH-1:0] w_test;
reg [TOTAL_WIDTH-1:0] modulus_test;

// 实例化顶层处理器
top_256bit_processor #(
    .TOTAL_WIDTH(TOTAL_WIDTH),
    .SEG_WIDTH(SEG_WIDTH)
) u_processor (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .add_mode(add_mode),
    .done(done),
    .x0(x0_test),
    .x1(x1_test),
    .w(w_test),
    .modulus(modulus_test),
    .result(result),
    .result_valid(result_valid)
);

// 时钟生成
initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

// 复位生成
initial begin
    rst_n = 1'b0;
    #(CLK_PERIOD*2) rst_n = 1'b1;
end

// 测试序列
initial begin
    // 初始化
    start = 1'b0;
    add_mode = 1'b1;  // 加法模式
    x0_test = {TOTAL_WIDTH{1'b0}};
    x1_test = {TOTAL_WIDTH{1'b0}};
    w_test = {TOTAL_WIDTH{1'b0}};
    modulus_test = 256'hFFFFFFFF000000010000000000000000;  // 256位模数
    
    // 等待复位完成
    #(CLK_PERIOD*3);
    
    // 测试用例1: 简单计算
    $display("=== 测试用例1: 简单计算 ===");
    x0_test = 256'h0000000000000001000000000000000200000000000000030000000000000004;
    x1_test = 256'h0000000000000005000000000000000600000000000000070000000000000008;
    w_test = 256'h0000000000000002000000000000000200000000000000020000000000000002;
    
    start = 1'b1;
    #CLK_PERIOD;
    start = 1'b0;
    
    // 等待计算完成
    wait(done);
    $display("计算结果: %h", result);
    
    // 测试用例2: 减法模式
    #(CLK_PERIOD*5);
    $display("=== 测试用例2: 减法模式 ===");
    add_mode = 1'b0;  // 减法模式
    x0_test = 256'h000000000000000A000000000000000A000000000000000A000000000000000A;
    x1_test = 256'h0000000000000002000000000000000200000000000000020000000000000002;
    w_test = 256'h0000000000000001000000000000000100000000000000010000000000000001;
    
    start = 1'b1;
    #CLK_PERIOD;
    start = 1'b0;
    
    // 等待计算完成
    wait(done);
    $display("计算结果: %h", result);
    
    // 完成测试
    #(CLK_PERIOD*10);
    $display("=== 测试完成 ===");
    $finish;
end

// 监控输出
always @(posedge clk) begin
    if (result_valid) begin
        $display("时间 %0t: 结果有效 = %h", $time, result);
    end
end

endmodule