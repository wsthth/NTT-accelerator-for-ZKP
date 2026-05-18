`timescale 1ns/1ps

// 64位分段乘法器（直接实现）
module seg_multiplier_64bit #(
    parameter WIDTH = 64
)(
    input wire [WIDTH-1:0] a,
    input wire [WIDTH-1:0] b,
    output wire [2*WIDTH-1:0] result  // 128位输出
);
    assign result = a * b;
endmodule