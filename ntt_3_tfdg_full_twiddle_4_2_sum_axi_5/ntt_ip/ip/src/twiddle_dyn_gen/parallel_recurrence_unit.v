// ================= 并行递推单元（创新点2） =================
module parallel_recurrence_unit #(
    parameter NUM_PARALLEL = 4,
    parameter DATA_WIDTH = 32
)(
    input  wire                          clk,
    input  wire                          reset_n,
    input  wire                          start,
    input  wire [DATA_WIDTH-1:0]         base_real,
    input  wire [DATA_WIDTH-1:0]         base_imag,
    input  wire [DATA_WIDTH-1:0]         omega_real,
    input  wire [DATA_WIDTH-1:0]         omega_imag,
    input  wire [DATA_WIDTH-1:0]         modulus,
    output reg  [DATA_WIDTH-1:0]         twiddle_real [0:NUM_PARALLEL-1],
    output reg  [DATA_WIDTH-1:0]         twiddle_imag [0:NUM_PARALLEL-1],
    output reg                           done
);

genvar i;
generate
    for (i = 0; i < NUM_PARALLEL; i = i + 1) begin : parallel_path
        // 每路计算：W_i = base * ω^i mod modulus
        // 使用递推关系：W_{i+1} = W_i * ω mod modulus
        
        reg [DATA_WIDTH-1:0] w_real_reg [0:2]; // 三级流水线
        reg [DATA_WIDTH-1:0] w_imag_reg [0:2];
        
        // 模乘单元（简化，实际需要实例化）
        always @(posedge clk) begin
            if (!reset_n) begin
                w_real_reg[0] <= 0;
                w_imag_reg[0] <= 0;
                w_real_reg[1] <= 0;
                w_imag_reg[1] <= 0;
                w_real_reg[2] <= 0;
                w_imag_reg[2] <= 0;
            end else if (start) begin
                if (i == 0) begin
                    // 第0路：初始化为base
                    w_real_reg[0] <= base_real;
                    w_imag_reg[0] <= base_imag;
                end else begin
                    // 其他路：从前一路获取
                    w_real_reg[0] <= parallel_path[i-1].w_real_reg[2];
                    w_imag_reg[0] <= parallel_path[i-1].w_imag_reg[2];
                end
                
                // 流水线推进：W_i = W_i * ω mod modulus
                // 实际这里应该调用模乘模块，简化实现
                w_real_reg[1] <= (w_real_reg[0] * omega_real - w_imag_reg[0] * omega_imag) % modulus;
                w_imag_reg[1] <= (w_real_reg[0] * omega_imag + w_imag_reg[0] * omega_real) % modulus;
                
                w_real_reg[2] <= w_real_reg[1];
                w_imag_reg[2] <= w_imag_reg[1];
                
                // 输出
                twiddle_real[i] <= w_real_reg[2];
                twiddle_imag[i] <= w_imag_reg[2];
            end
        end
    end
endgenerate

// 完成信号生成
reg [2:0] counter;
always @(posedge clk) begin
    if (!reset_n) begin
        counter <= 0;
        done <= 0;
    end else begin
        if (start) begin
            counter <= 1;
            done <= 0;
        end else if (counter > 0 && counter < NUM_PARALLEL+2) begin
            counter <= counter + 1;
        end else if (counter == NUM_PARALLEL+2) begin
            done <= 1;
            counter <= 0;
        end
    end
end


endmodule
