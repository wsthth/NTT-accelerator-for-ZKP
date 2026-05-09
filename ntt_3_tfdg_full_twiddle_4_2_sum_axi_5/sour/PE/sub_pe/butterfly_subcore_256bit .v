// ============================================================================
// 文件名: butterfly_subcore_256bit.v
// 描述: 256位蝶形运算子核，内部拆分为4个64位并行处理单元
// 功能: 计算 x0 ± x1 * w (模运算)
// ============================================================================
module butterfly_subcore_256bit #(
    parameter DATA_WIDTH = 256,           // 总数据位宽
    parameter SEG_WIDTH = 64,             // 每段位宽
    parameter SEG_COUNT = DATA_WIDTH / SEG_WIDTH,  // 分段数
    parameter MODULUS = 256'hFFFFFFFF0000000100000000000000000000000000000000  // 256位模数
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // 控制信号
    input wire start,        // 开始计算
    input wire add_mode,     // 1:加法(x0+x1*w), 0:减法(x0-x1*w)
    output reg done,         // 计算完成
    output reg busy,         // 忙碌状态
    
    // 256位数据输入
    input wire [DATA_WIDTH-1:0] x0,      // x0 (256位)
    input wire [DATA_WIDTH-1:0] x1,      // x1 (256位)
    input wire [DATA_WIDTH-1:0] w,       // w (256位)
    input wire [DATA_WIDTH-1:0] modulus, // 模数
    
    // 256位结果输出
    output reg [DATA_WIDTH-1:0] result,  // 计算结果
    output reg result_valid               // 结果有效
);

// ============================================================================
// 内部信号定义
// ============================================================================
reg [SEG_WIDTH-1:0] x0_segments [0:SEG_COUNT-1];
reg [SEG_WIDTH-1:0] x1_segments [0:SEG_COUNT-1];
reg [SEG_WIDTH-1:0] w_segments [0:SEG_COUNT-1];
reg [SEG_WIDTH-1:0] mod_segments [0:SEG_COUNT-1];
reg [SEG_WIDTH-1:0] intermediate_results [0:SEG_COUNT-1];

// 4个并行乘法器的控制信号
reg [3:0] mult_start;
wire [3:0] mult_done;
wire [3:0] mult_busy;
wire [SEG_WIDTH-1:0] mult_results [0:3];

// 状态机
reg [2:0] state;
reg [2:0] next_state;

localparam [2:0]
    STATE_IDLE     = 3'b000,
    STATE_SPLIT    = 3'b001,  // 拆分数据
    STATE_MULTIPLY = 3'b010,  // 并行乘法
    STATE_ACCUM    = 3'b011,  // 累加处理
    STATE_COMBINE  = 3'b100,  // 合并结果
    STATE_DONE     = 3'b101;

// 计数器
reg [3:0] cycle_counter;

// ============================================================================
// 64位乘法器模块（简单版本）
// ============================================================================
module seg_multiplier_64bit #(
    parameter WIDTH = 64
)(
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [WIDTH-1:0] a,
    input wire [WIDTH-1:0] b,
    input wire [WIDTH-1:0] modulus,
    output reg [WIDTH-1:0] result,
    output reg done,
    output reg busy
);

    reg [1:0] state;
    reg [WIDTH-1:0] a_reg, b_reg, mod_reg;
    reg [2*WIDTH-1:0] product;  // 128位乘积
    
    localparam [1:0]
        S_IDLE = 2'b00,
        S_MULT = 2'b01,
        S_MOD  = 2'b10,
        S_DONE = 2'b11;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            done <= 0;
            busy <= 0;
            result <= 0;
            a_reg <= 0;
            b_reg <= 0;
            mod_reg <= 0;
            product <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 0;
                    if (start) begin
                        a_reg <= a;
                        b_reg <= b;
                        mod_reg <= modulus;
                        busy <= 1;
                        state <= S_MULT;
                    end
                end
                
                S_MULT: begin
                    product <= a_reg * b_reg;
                    state <= S_MOD;
                end
                
                S_MOD: begin
                    // 简单的模约简（实际应用中应使用蒙哥马利约简）
                    result <= product % mod_reg;
                    state <= S_DONE;
                end
                
                S_DONE: begin
                    done <= 1;
                    busy <= 0;
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule

// ============================================================================
// 模加/模减单元
// ============================================================================
module modular_operation_64bit #(
    parameter WIDTH = 64
)(
    input wire [WIDTH-1:0] a,
    input wire [WIDTH-1:0] b,
    input wire [WIDTH-1:0] modulus,
    input wire add_mode,  // 1:加法, 0:减法
    output reg [WIDTH-1:0] result
);
    
    always @(*) begin
        if (add_mode) begin
            // 加法: (a + b) mod modulus
            if (a + b >= modulus) begin
                result = a + b - modulus;
            end else begin
                result = a + b;
            end
        end else begin
            // 减法: (a - b + modulus) mod modulus
            if (a >= b) begin
                result = a - b;
            end else begin
                result = a + modulus - b;
            end
        end
    end
    
endmodule

// ============================================================================
// 实例化4个64位乘法器
// ============================================================================
genvar i;
generate
    for (i = 0; i < 4; i = i + 1) begin : gen_multipliers
        seg_multiplier_64bit #(
            .WIDTH(SEG_WIDTH)
        ) u_multiplier (
            .clk(clk),
            .rst_n(rst_n),
            .start(mult_start[i]),
            .a(x1_segments[i]),
            .b(w_segments[i]),
            .modulus(mod_segments[i]),
            .result(mult_results[i]),
            .done(mult_done[i]),
            .busy(mult_busy[i])
        );
    end
endgenerate

// ============================================================================
// 实例化4个模运算单元
// ============================================================================
wire [SEG_WIDTH-1:0] op_results [0:3];
generate
    for (i = 0; i < 4; i = i + 1) begin : gen_operations
        modular_operation_64bit #(
            .WIDTH(SEG_WIDTH)
        ) u_operation (
            .a(x0_segments[i]),
            .b(mult_results[i]),
            .modulus(mod_segments[i]),
            .add_mode(add_mode),
            .result(op_results[i])
        );
    end
endgenerate

// ============================================================================
// 主状态机
// ============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= STATE_IDLE;
        done <= 0;
        busy <= 0;
        result <= 0;
        result_valid <= 0;
        cycle_counter <= 0;
        mult_start <= 4'b0000;
    end else begin
        state <= next_state;
        
        case (state)
            STATE_IDLE: begin
                done <= 0;
                busy <= 0;
                result_valid <= 0;
                cycle_counter <= 0;
                
                if (start) begin
                    // 开始计算
                    busy <= 1;
                    next_state <= STATE_SPLIT;
                end else begin
                    next_state <= STATE_IDLE;
                end
            end
            
            STATE_SPLIT: begin
                // 拆分256位数据为4个64位分段
                x0_segments[0] <= x0[63:0];
                x0_segments[1] <= x0[127:64];
                x0_segments[2] <= x0[191:128];
                x0_segments[3] <= x0[255:192];
                
                x1_segments[0] <= x1[63:0];
                x1_segments[1] <= x1[127:64];
                x1_segments[2] <= x1[191:128];
                x1_segments[3] <= x1[255:192];
                
                w_segments[0] <= w[63:0];
                w_segments[1] <= w[127:64];
                w_segments[2] <= w[191:128];
                w_segments[3] <= w[255:192];
                
                // 模数拆分（简化处理，使用低64位）
                mod_segments[0] <= modulus[63:0];
                mod_segments[1] <= modulus[63:0];
                mod_segments[2] <= modulus[63:0];
                mod_segments[3] <= modulus[63:0];
                
                cycle_counter <= cycle_counter + 1;
                next_state <= STATE_MULTIPLY;
            end
            
            STATE_MULTIPLY: begin
                // 启动4个并行乘法器
                mult_start <= 4'b1111;
                cycle_counter <= cycle_counter + 1;
                
                // 等待乘法完成
                if (mult_done == 4'b1111) begin
                    mult_start <= 4'b0000;
                    next_state <= STATE_ACCUM;
                end else begin
                    next_state <= STATE_MULTIPLY;
                end
            end
            
            STATE_ACCUM: begin
                // 乘法器结果已经准备好，模运算单元会自动计算
                // 将结果保存到中间寄存器
                intermediate_results[0] <= op_results[0];
                intermediate_results[1] <= op_results[1];
                intermediate_results[2] <= op_results[2];
                intermediate_results[3] <= op_results[3];
                
                cycle_counter <= cycle_counter + 1;
                next_state <= STATE_COMBINE;
            end
            
            STATE_COMBINE: begin
                // 合并4个64位结果为256位
                result <= {
                    intermediate_results[3],
                    intermediate_results[2],
                    intermediate_results[1],
                    intermediate_results[0]
                };
                
                cycle_counter <= cycle_counter + 1;
                next_state <= STATE_DONE;
            end
            
            STATE_DONE: begin
                result_valid <= 1;
                done <= 1;
                busy <= 0;
                
                if (!start) begin
                    next_state <= STATE_IDLE;
                    result_valid <= 0;
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

// ============================================================================
// 性能监控（可选）
// ============================================================================
reg [7:0] latency;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        latency <= 8'd0;
    end else if (start && state == STATE_IDLE) begin
        latency <= 8'd1;
    end else if (busy) begin
        latency <= latency + 8'd1;
    end
end

endmodule

// ============================================================================
// 文件名: ntt_butterfly_unit.v
// ============================================================================
// 更完整的蝶形单元，包含两个子核（一个加法分支，一个减法分支）
module ntt_butterfly_unit #(
    parameter DATA_WIDTH = 256,
    parameter SEG_WIDTH = 64
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // 控制信号
    input wire start,
    output wire done,
    
    // 数据输入
    input wire [DATA_WIDTH-1:0] x0,
    input wire [DATA_WIDTH-1:0] x1,
    input wire [DATA_WIDTH-1:0] w,
    input wire [DATA_WIDTH-1:0] modulus,
    
    // 蝶形运算的两个输出
    output wire [DATA_WIDTH-1:0] out0,  // x0 + x1*w
    output wire [DATA_WIDTH-1:0] out1,  // x0 - x1*w
    output wire outputs_valid
);

// 两个子核：一个计算加法分支，一个计算减法分支
wire add_done, sub_done;
wire add_valid, sub_valid;
wire [DATA_WIDTH-1:0] add_result, sub_result;

// 加法子核
butterfly_subcore_256bit #(
    .DATA_WIDTH(DATA_WIDTH),
    .SEG_WIDTH(SEG_WIDTH),
    .MODULUS(256'hFFFFFFFF0000000100000000000000000000000000000000)
) u_add_subcore (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .add_mode(1'b1),  // 加法模式
    .done(add_done),
    .busy(),
    .x0(x0),
    .x1(x1),
    .w(w),
    .modulus(modulus),
    .result(add_result),
    .result_valid(add_valid)
);

// 减法子核
butterfly_subcore_256bit #(
    .DATA_WIDTH(DATA_WIDTH),
    .SEG_WIDTH(SEG_WIDTH),
    .MODULUS(256'hFFFFFFFF0000000100000000000000000000000000000000)
) u_sub_subcore (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .add_mode(1'b0),  // 减法模式
    .done(sub_done),
    .busy(),
    .x0(x0),
    .x1(x1),
    .w(w),
    .modulus(modulus),
    .result(sub_result),
    .result_valid(sub_valid)
);

// 输出
assign out0 = add_result;
assign out1 = sub_result;
assign outputs_valid = add_valid & sub_valid;  // 两个都有效时输出有效
assign done = add_done & sub_done;             // 两个都完成时完成

endmodule

// ============================================================================
// 测试模块
// ============================================================================
module test_butterfly_subcore;

parameter CLK_PERIOD = 10;
parameter DATA_WIDTH = 256;
parameter SEG_WIDTH = 64;

reg clk;
reg rst_n;
reg start;
reg add_mode;
wire done;
wire [DATA_WIDTH-1:0] result;
wire result_valid;

// 测试数据
reg [DATA_WIDTH-1:0] x0_test;
reg [DATA_WIDTH-1:0] x1_test;
reg [DATA_WIDTH-1:0] w_test;
reg [DATA_WIDTH-1:0] modulus_test;

// 实例化子核
butterfly_subcore_256bit #(
    .DATA_WIDTH(DATA_WIDTH),
    .SEG_WIDTH(SEG_WIDTH)
) u_subcore (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .add_mode(add_mode),
    .done(done),
    .busy(),
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
    add_mode = 1'b1;
    
    // 设置测试数据
    x0_test = 256'h0000000000000001000000000000000200000000000000030000000000000004;
    x1_test = 256'h0000000000000005000000000000000600000000000000070000000000000008;
    w_test = 256'h0000000000000002000000000000000200000000000000020000000000000002;
    modulus_test = 256'hFFFFFFFF0000000100000000000000000000000000000000;
    
    // 等待复位完成
    #(CLK_PERIOD*3);
    
    // 测试用例1：加法
    $display("=== 测试用例1：加法模式 ===");
    $display("x0 = %h", x0_test);
    $display("x1 = %h", x1_test);
    $display("w = %h", w_test);
    
    start = 1'b1;
    #CLK_PERIOD;
    start = 1'b0;
    
    // 等待计算完成
    wait(done);
    $display("加法结果 = %h", result);
    $display("计算周期数：%d", u_subcore.latency);
    
    // 测试用例2：减法
    #(CLK_PERIOD*5);
    $display("=== 测试用例2：减法模式 ===");
    add_mode = 1'b0;
    
    start = 1'b1;
    #CLK_PERIOD;
    start = 1'b0;
    
    // 等待计算完成
    wait(done);
    $display("减法结果 = %h", result);
    $display("计算周期数：%d", u_subcore.latency);
    
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