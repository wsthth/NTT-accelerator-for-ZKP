// parallel_recurrence_unit_packed_fixed.v
// 修正了Vivado兼容性问题
`timescale 1ns / 1ps

module parallel_recurrence_unit_packed_fixed #(
    parameter NUM_PARALLEL = 4,      // 并行路数
    parameter DATA_WIDTH = 32        // 数据位宽
)(
    // ================= 时钟与复位 =================
    input  wire                          clk,
    input  wire                          reset_n,
    
    // ================= 控制信号 =================
    input  wire                          start,        // 开始生成
    
    // ================= 输入数据 =================
    input  wire [DATA_WIDTH-1:0]         base_real,    // 基础值实部
    input  wire [DATA_WIDTH-1:0]         base_imag,    // 基础值虚部
    input  wire [DATA_WIDTH-1:0]         omega_real,   // 单位根实部
    input  wire [DATA_WIDTH-1:0]         omega_imag,   // 单位根虚部
    input  wire [DATA_WIDTH-1:0]         modulus,      // 模数（32位）
    
    // ================= 输出数据（打包数组） =================
    output wire [DATA_WIDTH*NUM_PARALLEL-1:0] twiddle_real_packed, // 旋转因子实部（打包）
    output wire [DATA_WIDTH*NUM_PARALLEL-1:0] twiddle_imag_packed, // 旋转因子虚部（打包）
    
    // ================= 状态指示 =================
    output reg                           done           // 生成完成
);

// ================= 内部寄存器数组 =================
// 使用二维寄存器数组替代生成块内的交叉引用
reg [DATA_WIDTH-1:0] w_real_pipeline [0:NUM_PARALLEL-1][0:2];  // [路径][流水级]
reg [DATA_WIDTH-1:0] w_imag_pipeline [0:NUM_PARALLEL-1][0:2];

// ================= 生成语句：连接打包输出 =================
genvar i;
generate
    for (i = 0; i < NUM_PARALLEL; i = i + 1) begin : pack_outputs
        // 将内部寄存器的最后一级输出打包
        assign twiddle_real_packed[i*DATA_WIDTH +: DATA_WIDTH] = w_real_pipeline[i][2];
        assign twiddle_imag_packed[i*DATA_WIDTH +: DATA_WIDTH] = w_imag_pipeline[i][2];
    end
endgenerate

// ================= 并行计算逻辑（修正交叉引用问题） =================
// 第0路的特殊处理
always @(posedge clk) begin
    if (!reset_n) begin
        // 复位第0路
        w_real_pipeline[0][0] <= 0;
        w_imag_pipeline[0][0] <= 0;
        w_real_pipeline[0][1] <= 0;
        w_imag_pipeline[0][1] <= 0;
        w_real_pipeline[0][2] <= 0;
        w_imag_pipeline[0][2] <= 0;
    end else if (start) begin
        // 第0路：初始化为基础值
        w_real_pipeline[0][0] <= base_real;
        w_imag_pipeline[0][0] <= base_imag;
        
        // 第0路的复数乘法（简化实现）
        w_real_pipeline[0][1] <= (w_real_pipeline[0][0] * omega_real - w_imag_pipeline[0][0] * omega_imag) % modulus;
        w_imag_pipeline[0][1] <= (w_real_pipeline[0][0] * omega_imag + w_imag_pipeline[0][0] * omega_real) % modulus;
        
        // 流水线推进
        w_real_pipeline[0][2] <= w_real_pipeline[0][1];
        w_imag_pipeline[0][2] <= w_imag_pipeline[0][1];
    end
end

// 其他路的处理（避免使用生成块交叉引用）
generate
    for (i = 1; i < NUM_PARALLEL; i = i + 1) begin : other_paths
        always @(posedge clk) begin
            if (!reset_n) begin
                // 复位当前路
                w_real_pipeline[i][0] <= 0;
                w_imag_pipeline[i][0] <= 0;
                w_real_pipeline[i][1] <= 0;
                w_imag_pipeline[i][1] <= 0;
                w_real_pipeline[i][2] <= 0;
                w_imag_pipeline[i][2] <= 0;
            end else if (start) begin
                // 使用前一路的输出作为当前路的输入
                w_real_pipeline[i][0] <= w_real_pipeline[i-1][2];
                w_imag_pipeline[i][0] <= w_imag_pipeline[i-1][2];
                
                // 复数乘法（简化实现）
                w_real_pipeline[i][1] <= (w_real_pipeline[i][0] * omega_real - w_imag_pipeline[i][0] * omega_imag) % modulus;
                w_imag_pipeline[i][1] <= (w_real_pipeline[i][0] * omega_imag + w_imag_pipeline[i][0] * omega_real) % modulus;
                
                // 流水线推进
                w_real_pipeline[i][2] <= w_real_pipeline[i][1];
                w_imag_pipeline[i][2] <= w_imag_pipeline[i][1];
            end
        end
    end
endgenerate

// ================= 完成信号生成 =================
reg [2:0] counter;
always @(posedge clk) begin
    if (!reset_n) begin
        counter <= 0;
        done <= 0;
    end else begin
        if (start) begin
            counter <= 1;
            done <= 0;
        end else if (counter > 0 && counter < NUM_PARALLEL + 2) begin
            counter <= counter + 1;
        end else if (counter == NUM_PARALLEL + 2) begin
            done <= 1;
            counter <= 0;
        end
    end
end

endmodule