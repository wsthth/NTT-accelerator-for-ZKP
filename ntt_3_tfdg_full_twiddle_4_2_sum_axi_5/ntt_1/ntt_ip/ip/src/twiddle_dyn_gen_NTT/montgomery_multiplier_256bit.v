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
localparam START_REDUCE = 3'd2;
localparam REDUCE = 3'd3;
localparam DONE   = 3'd4;

// 512位中间乘积
reg [2*TOTAL_BITS-1:0] product_512;
reg pipeline_start;

// 蒙哥马利约简模块实例
wire mont_reduction_done;
wire [TOTAL_BITS-1:0] mont_reduction_result;

// 计算乘积的组合逻辑
wire [2*TOTAL_BITS-1:0] product_wire;
assign product_wire = {256'd0, a_mont} * {256'd0, b_mont};

montgomery_pipeline #(
    .TOTAL_BITS(TOTAL_BITS),
    .SEG_BITS(SEG_BITS),
    .SEG_CNT(TOTAL_BITS/SEG_BITS),
    .PIPELINE_STAGES(4)
) reduction_inst (
    .clk(clk),
    .rst_n(reset_n),
    .start(pipeline_start),
    .N(N),
    .N_prime(N_prime),
    .t(product_512),           // 使用寄存器的乘积
    .mont_result(mont_reduction_result),
    .valid_out(),
    .done(mont_reduction_done)
);

// 控制逻辑
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        state <= IDLE;
        product_512 <= 0;
        result_mont <= 0;
        done <= 0;
        pipeline_start <= 0;
    end else begin
        pipeline_start <= 0;
        done <= 0;
        
        case (state)
            IDLE: begin
                if (start) begin
                    // 寄存乘积，避免组合逻辑路径过长
                    product_512 <= product_wire;
                    state <= START_REDUCE;
                end
            end
            
            START_REDUCE: begin
                // 启动蒙哥马利约简
                pipeline_start <= 1;
                state <= REDUCE;
            end
            
            REDUCE: begin
                pipeline_start <= 0;
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