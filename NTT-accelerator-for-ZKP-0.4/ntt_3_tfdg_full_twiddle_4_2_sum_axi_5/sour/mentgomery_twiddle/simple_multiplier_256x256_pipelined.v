// simple_multiplier_256x256.v
`timescale 1ns / 1ps

module simple_multiplier_256x256_pipelined(
    input wire clk,
    input wire reset_n,
    input wire start,
    
    // 输入
    input wire [255:0] a,
    input wire [255:0] b,
    
    // 输出乘积（512位）
    output reg [511:0] product,
    output reg done
);

// 状态机
reg [1:0] state;
localparam IDLE = 2'd0;
localparam MULTIPLY = 2'd1;
localparam DONE = 2'd2;

// 组合逻辑乘法
wire [511:0] product_wire;
assign product_wire = {256'd0, a} * {256'd0, b};

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        state <= IDLE;
        product <= 0;
        done <= 0;
    end else begin
        done <= 0;
        
        case (state)
            IDLE: begin
                if (start) begin
                    state <= MULTIPLY;
                end
            end
            
            MULTIPLY: begin
                // 将组合逻辑的乘积结果锁存到寄存器
                product <= product_wire;
                state <= DONE;
            end
            
            DONE: begin
                done <= 1;
                state <= IDLE;
            end
        endcase
    end
end

endmodule