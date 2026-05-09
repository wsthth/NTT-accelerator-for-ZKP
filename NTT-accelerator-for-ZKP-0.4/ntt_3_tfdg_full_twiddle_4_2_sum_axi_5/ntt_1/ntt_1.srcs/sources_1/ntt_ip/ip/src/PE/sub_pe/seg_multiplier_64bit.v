// 64位乘法器模块（组合逻辑）
module seg_multiplier_64bit #(
    parameter WIDTH = 64
)(
    input wire [WIDTH-1:0] a,
    input wire [WIDTH-1:0] b,
    output wire [2*WIDTH-1:0] result  // 128位结果
);
    assign result = a * b;
endmodule
