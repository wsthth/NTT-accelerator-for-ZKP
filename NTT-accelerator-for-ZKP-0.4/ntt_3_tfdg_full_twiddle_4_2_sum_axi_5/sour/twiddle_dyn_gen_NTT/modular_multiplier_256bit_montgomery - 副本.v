// ============================================================================
// 256-bit Montgomery Modular Multiplier
// ============================================================================
// 输入: a, b (normal domain numbers)
// 输出: result = (a * b) mod N
// 需要预计算的参数:
//   - N: 模数 (256位素数)
//   - Np: -N^{-1} mod 2^256
//   - R2: 2^512 mod N
// ============================================================================

// ============================================================================
// 256-bit Montgomery Modular Multiplier (Corrected)
// ============================================================================

module modular_multiplier_256bit (
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [255:0] a,
    input wire [255:0] b,
    input wire [255:0] N,
    input wire [255:0] Np,
    input wire [255:0] R2_mod_N,
    
    output reg [255:0] result,
    output reg done,
    output reg busy
);

// ============================================================================
// Local Parameters and Registers
// ============================================================================
localparam [2:0]
    S_IDLE     = 3'd0,
    S_CONV_A   = 3'd1,
    S_CONV_B   = 3'd2,
    S_MULTIPLY = 3'd3,
    S_CONV_OUT = 3'd4,
    S_DONE     = 3'd5;

reg [2:0] state;
reg [255:0] a_reg, b_reg;
reg [255:0] a_mont, b_mont;
reg [255:0] temp_result;

// Montgomery multiplier control signals
reg mont_start;
wire mont_done;
wire [255:0] mont_result;

// ============================================================================
// Montgomery Multiplier Instance
// ============================================================================
// 假设montgomery_multiplier_256bit模块有以下接口：
// module montgomery_multiplier_256bit (
//     input wire clk,
//     input wire reset_n,
//     input wire start,
//     input wire [255:0] a_mont,
//     input wire [255:0] b_mont,
//     input wire [255:0] N,
//     input wire [255:0] N_prime,
//     output reg [255:0] result_mont,
//     output reg done
// );
montgomery_multiplier_256bit mul_inst(
    .clk(clk),
    .reset_n(rst_n),
    .start(mont_start),
    .a_mont(a_reg),
    .b_mont(b_reg),
    .N(N),
    .N_prime(Np),
    .result_mont(mont_result),
    .done(mont_done)
);

// ============================================================================
// State Machine
// ============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= S_IDLE;
        done <= 1'b0;
        busy <= 1'b0;
        a_mont <= 256'd0;
        b_mont <= 256'd0;
        result <= 256'd0;
        mont_start <= 1'b0;
        temp_result <= 256'd0;
        a_reg <= 256'd0;
        b_reg <= 256'd0;
    end else begin
        case (state)
            S_IDLE: begin
                done <= 1'b0;
                if (start) begin
                    busy <= 1'b1;
                    // Store inputs
                    a_reg <= a;
                    b_reg <= b;
                    state <= S_CONV_A;
                    mont_start <= 1'b0;
                end else begin
                    busy <= 1'b0;
                end
            end
            
            S_CONV_A: begin
                // Convert a to Montgomery domain: a * R2_mod_N
                a_reg <= a;          // 普通域的a
                b_reg <= R2_mod_N;   // R^2 mod N
                mont_start <= 1'b1;
                if (mont_done) begin
                    a_mont <= mont_result;  // 现在a在蒙哥马利域
                    mont_start <= 1'b0;
                    state <= S_CONV_B;
                end
            end
            
            S_CONV_B: begin
                // Convert b to Montgomery domain: b * R2_mod_N
                a_reg <= b;          // 普通域的b
                b_reg <= R2_mod_N;   // R^2 mod N
                mont_start <= 1'b1;
                if (mont_done) begin
                    b_mont <= mont_result;  // 现在b在蒙哥马利域
                    mont_start <= 1'b0;
                    state <= S_MULTIPLY;
                end
            end
            
            S_MULTIPLY: begin
                // Multiply in Montgomery domain: a_mont * b_mont
                a_reg <= a_mont;
                b_reg <= b_mont;
                mont_start <= 1'b1;
                if (mont_done) begin
                    temp_result <= mont_result;  // 蒙哥马利域的结果
                    mont_start <= 1'b0;
                    state <= S_CONV_OUT;
                end
            end
            
            S_CONV_OUT: begin
                // Convert back to normal domain: result * 1
                a_reg <= temp_result;
                b_reg <= 256'd1;  // Multiply by 1 to get out of Montgomery domain
                mont_start <= 1'b1;
                if (mont_done) begin
                    result <= mont_result;  // 普通域的结果
                    mont_start <= 1'b0;
                    state <= S_DONE;
                end
            end
            
            S_DONE: begin
                done <= 1'b1;
                busy <= 1'b0;
                state <= S_IDLE;
            end
            
            default: begin
                state <= S_IDLE;
            end
        endcase
    end
end

endmodule
