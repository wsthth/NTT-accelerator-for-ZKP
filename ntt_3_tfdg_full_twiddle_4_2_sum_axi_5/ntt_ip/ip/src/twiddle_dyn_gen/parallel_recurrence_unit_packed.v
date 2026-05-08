// parallel_recurrence_unit_packed_fixed_fixed.v
`timescale 1ns / 1ps

module parallel_recurrence_unit_packed_fixed #(
    parameter NUM_PARALLEL = 4,
    parameter DATA_WIDTH = 32
)(
    input wire clk,
    input wire reset_n,
    input wire start,
    input wire [DATA_WIDTH-1:0] base_real,
    input wire [DATA_WIDTH-1:0] base_imag,
    input wire [DATA_WIDTH-1:0] omega_real,
    input wire [DATA_WIDTH-1:0] omega_imag,
    input wire [DATA_WIDTH-1:0] modulus,
    output wire [DATA_WIDTH*NUM_PARALLEL-1:0] twiddle_real_packed,
    output wire [DATA_WIDTH*NUM_PARALLEL-1:0] twiddle_imag_packed,
    output reg done
);

// 内部寄存器数组
reg [DATA_WIDTH-1:0] w_real_pipeline [0:NUM_PARALLEL-1][0:2];
reg [DATA_WIDTH-1:0] w_imag_pipeline [0:NUM_PARALLEL-1][0:2];

// 生成输出
genvar i;
generate
    for (i = 0; i < NUM_PARALLEL; i = i + 1) begin : pack_outputs
        assign twiddle_real_packed[i*DATA_WIDTH +: DATA_WIDTH] = w_real_pipeline[i][2];
        assign twiddle_imag_packed[i*DATA_WIDTH +: DATA_WIDTH] = w_imag_pipeline[i][2];
    end
endgenerate

// 控制逻辑
reg [2:0] state;
reg [3:0] counter;

localparam IDLE = 3'd0;
localparam INIT = 3'd1;
localparam CALC = 3'd2;
localparam DONE = 3'd3;

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        state <= IDLE;
        done <= 0;
        counter <= 0;
        
        // 复位所有寄存器
        for (integer j = 0; j < NUM_PARALLEL; j = j + 1) begin
            for (integer k = 0; k < 3; k = k + 1) begin
                w_real_pipeline[j][k] <= 0;
                w_imag_pipeline[j][k] <= 0;
            end
        end
        
        $display("[%t] parallel_unit: Reset", $time);
    end else begin
        case (state)
            IDLE: begin
                if (start) begin
                    state <= INIT;
                    counter <= 0;
                    $display("[%t] parallel_unit: Starting with base_real=%h, base_imag=%h", 
                             $time, base_real, base_imag);
                end
            end
            
            INIT: begin
                // 初始化第0路的第0级
                w_real_pipeline[0][0] <= base_real;
                w_imag_pipeline[0][0] <= base_imag;
                
                state <= CALC;
                counter <= 1;
                $display("[%t] parallel_unit: Initialized path 0", $time);
            end
            
            CALC: begin
                counter <= counter + 1;
                
                // 调试：显示当前状态
                $display("[%t] parallel_unit: CALC cycle %d", $time, counter);
                
                // 第0路的计算
                if (counter == 1) begin
                    // 第0路的第1级计算
                    // 简化：直接传递，不进行计算
                    w_real_pipeline[0][1] <= w_real_pipeline[0][0];
                    w_imag_pipeline[0][1] <= w_imag_pipeline[0][0];
                end
                
                if (counter == 2) begin
                    // 第0路的第2级计算（最终输出级）
                    w_real_pipeline[0][2] <= w_real_pipeline[0][1];
                    w_imag_pipeline[0][2] <= w_imag_pipeline[0][1];
                    
                    // 同时初始化第1路的第0级
                    w_real_pipeline[1][0] <= w_real_pipeline[0][2];
                    w_imag_pipeline[1][0] <= w_imag_pipeline[0][2];
                end
                
                if (counter == 3) begin
                    // 第1路的第1级
                    w_real_pipeline[1][1] <= w_real_pipeline[1][0];
                    w_imag_pipeline[1][1] <= w_imag_pipeline[1][0];
                end
                
                if (counter == 4) begin
                    // 第1路的第2级
                    w_real_pipeline[1][2] <= w_real_pipeline[1][1];
                    w_imag_pipeline[1][2] <= w_imag_pipeline[1][1];
                    
                    // 同时初始化第2路的第0级
                    w_real_pipeline[2][0] <= w_real_pipeline[1][2];
                    w_imag_pipeline[2][0] <= w_imag_pipeline[1][2];
                end
                
                if (counter == 5) begin
                    // 第2路的第1级
                    w_real_pipeline[2][1] <= w_real_pipeline[2][0];
                    w_imag_pipeline[2][1] <= w_imag_pipeline[2][0];
                end
                
                if (counter == 6) begin
                    // 第2路的第2级
                    w_real_pipeline[2][2] <= w_real_pipeline[2][1];
                    w_imag_pipeline[2][2] <= w_imag_pipeline[2][1];
                    
                    // 同时初始化第3路的第0级
                    w_real_pipeline[3][0] <= w_real_pipeline[2][2];
                    w_imag_pipeline[3][0] <= w_imag_pipeline[2][2];
                end
                
                if (counter == 7) begin
                    // 第3路的第1级
                    w_real_pipeline[3][1] <= w_real_pipeline[3][0];
                    w_imag_pipeline[3][1] <= w_imag_pipeline[3][0];
                end
                
                if (counter == 8) begin
                    // 第3路的第2级（所有路径完成）
                    w_real_pipeline[3][2] <= w_real_pipeline[3][1];
                    w_imag_pipeline[3][2] <= w_imag_pipeline[3][1];
                    
                    state <= DONE;
                end
            end
            
            DONE: begin
                done <= 1;
                state <= IDLE;
                
                // 打印所有结果
                $display("[%t] parallel_unit: All calculations done", $time);
                for (integer m = 0; m < NUM_PARALLEL; m = m + 1) begin
                    $display("  Path[%0d]: real=%h, imag=%h", 
                             m, w_real_pipeline[m][2], w_imag_pipeline[m][2]);
                end
            end
            
            default: state <= IDLE;
        endcase
    end
end

endmodule