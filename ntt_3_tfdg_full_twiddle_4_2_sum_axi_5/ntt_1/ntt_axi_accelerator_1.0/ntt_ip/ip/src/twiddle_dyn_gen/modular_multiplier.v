// ================= 模乘子模块 =================
module modular_multiplier #(
    parameter DATA_WIDTH = 32,
    parameter MODULUS_WIDTH = 16
)(
    input  wire                          clk,
    input  wire                          reset_n,
    input  wire                          start,
    input  wire [DATA_WIDTH-1:0]         a_real,
    input  wire [DATA_WIDTH-1:0]         a_imag,
    input  wire [DATA_WIDTH-1:0]         b_real,
    input  wire [DATA_WIDTH-1:0]         b_imag,
    input  wire [MODULUS_WIDTH-1:0]      modulus,
    output reg  [DATA_WIDTH-1:0]         result_real,
    output reg  [DATA_WIDTH-1:0]         result_imag,
    output reg                           done,
    output reg                           error
);

// 复数模乘：(a+bi)*(c+di) = (ac-bd) + (ad+bc)i mod modulus
// 每个乘法都需要模约减

reg [2:0] state;
localparam S_IDLE = 3'b000;
localparam S_MUL_AC = 3'b001;
localparam S_MUL_BD = 3'b010;
localparam S_MUL_AD = 3'b011;
localparam S_MUL_BC = 3'b100;
localparam S_MOD_RED = 3'b101;
localparam S_DONE = 3'b110;

reg [DATA_WIDTH*2-1:0] ac, bd, ad, bc; // 乘法中间结果
reg [DATA_WIDTH-1:0] ac_mod, bd_mod, ad_mod, bc_mod;

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        state <= S_IDLE;
        done <= 0;
        error <= 0;
    end else begin
        case (state)
            S_IDLE: begin
                if (start) begin
                    state <= S_MUL_AC;
                    done <= 0;
                    error <= 0;
                end
            end
            
            S_MUL_AC: begin
                ac <= a_real * b_real;
                state <= S_MUL_BD;
            end
            
            S_MUL_BD: begin
                bd <= a_imag * b_imag;
                state <= S_MUL_AD;
            end
            
            S_MUL_AD: begin
                ad <= a_real * b_imag;
                state <= S_MUL_BC;
            end
            
            S_MUL_BC: begin
                bc <= a_imag * b_real;
                state <= S_MOD_RED;
            end
            
            S_MOD_RED: begin
                // 模约减
                ac_mod <= ac % modulus;
                bd_mod <= bd % modulus;
                ad_mod <= ad % modulus;
                bc_mod <= bc % modulus;
                state <= S_DONE;
            end
            
            S_DONE: begin
                // 计算最终结果
                if (ac_mod >= bd_mod) begin
                    result_real <= ac_mod - bd_mod;
                end else begin
                    result_real <= modulus - (bd_mod - ac_mod);
                end
                
                // 计算虚部
                if (ad_mod + bc_mod >= modulus) begin
                    result_imag <= ad_mod + bc_mod - modulus;
                end else begin
                    result_imag <= ad_mod + bc_mod;
                end
                
                done <= 1;
                state <= S_IDLE;
                
                // 错误检测
                if (modulus == 0) begin
                    error <= 1;
                end
            end
        endcase
    end
end

endmodule
