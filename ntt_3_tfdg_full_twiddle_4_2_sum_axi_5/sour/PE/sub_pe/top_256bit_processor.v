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
