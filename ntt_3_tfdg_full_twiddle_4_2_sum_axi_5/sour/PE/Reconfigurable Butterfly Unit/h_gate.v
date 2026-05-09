// ============================================================================
// 可重构的H门加法器阵列（实现矩阵A和C）
// ============================================================================

// H门：同时计算和与差
module h_gate #(
    parameter WIDTH = DATA_WIDTH
)(
    input wire clk,
    input wire rst_n,
    input wire enable,
    input wire [WIDTH-1:0] a,
    input wire [WIDTH-1:0] b,
    output reg [WIDTH-1:0] sum,
    output reg [WIDTH-1:0] diff,
    output reg done
);
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sum <= {WIDTH{1'b0}};
            diff <= {WIDTH{1'b0}};
            done <= 1'b0;
        end else if (enable) begin
            // 同时计算和与差（模运算）
            if (a + b >= modulus) begin
                sum <= a + b - modulus;
            end else begin
                sum <= a + b;
            end
            
            if (a >= b) begin
                diff <= a - b;
            end else begin
                diff <= a + modulus - b;
            end
            
            done <= 1'b1;
        end else begin
            done <= 1'b0;
        end
    end
endmodule
