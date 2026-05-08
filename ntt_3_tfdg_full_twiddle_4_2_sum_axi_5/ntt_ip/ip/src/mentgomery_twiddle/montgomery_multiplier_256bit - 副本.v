// montgomery_multiplier_256bit.v
`timescale 1ns / 1ps

module montgomery_multiplier_256bit #(
    parameter TOTAL_BITS = 256,
    parameter SEG_BITS = 64
)(
    input wire clk,
    input wire reset_n,
    input wire start,
    
    // 输入（蒙哥马利域）
    input wire [TOTAL_BITS-1:0] a_mont,
    input wire [TOTAL_BITS-1:0] b_mont,
    
    // 模数及预计算参数
    input wire [TOTAL_BITS-1:0] N,
    input wire [TOTAL_BITS-1:0] N_prime,
    
    // 输出（蒙哥马利域）
    output reg [TOTAL_BITS-1:0] result_mont,
    output reg done
);

// 内部信号
reg [2:0] state;
localparam IDLE   = 3'd0;
localparam CALC   = 3'd1;
localparam REDUCE = 3'd2;
localparam DONE   = 3'd3;

// 512位中间乘积
reg [2*TOTAL_BITS-1:0] product_512;

// 蒙哥马利约简模块实例
wire mont_reduction_done;
wire [TOTAL_BITS-1:0] mont_reduction_result;

// 确保 montgomery_pipeline 模块存在且接口正确
montgomery_pipeline #(
    .TOTAL_BITS(TOTAL_BITS),
    .SEG_BITS(SEG_BITS),
    .SEG_CNT(TOTAL_BITS/SEG_BITS),
    .PIPELINE_STAGES(4)
) reduction_inst (
    .clk(clk),
    .rst_n(reset_n),
    .start(start),  // 修改：使用模块的start信号
    .N(N),
    .N_prime(N_prime),
    .t(product_512),           // 512位输入
    .mont_result(mont_reduction_result),
    .valid_out(),              // 未使用
    .done(mont_reduction_done)
);

// 控制逻辑
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        state <= IDLE;
        product_512 <= 0;
        result_mont <= 0;
        done <= 0;
    end else begin
        case (state)
            IDLE: begin
                done <= 0;
                if (start) begin
                    // 计算 a_mont * b_mont (512位)
                    product_512 <= a_mont * b_mont;
                    state <= CALC;
                end
            end
            
            CALC: begin
                // 乘积已计算，等待约简模块完成
                if (mont_reduction_done) begin
                    result_mont <= mont_reduction_result;
                    state <= DONE;
                end
            end
            
            DONE: begin
                done <= 1;
                state <= IDLE;
            end
            
            default: state <= IDLE;
        endcase
    end
end

endmodule