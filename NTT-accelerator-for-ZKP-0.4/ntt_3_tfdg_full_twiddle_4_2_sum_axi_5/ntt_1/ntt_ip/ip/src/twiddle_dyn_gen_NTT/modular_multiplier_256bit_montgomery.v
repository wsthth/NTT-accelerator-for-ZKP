// ============================================================================
// Parameterized Montgomery Modular Multiplier
// ============================================================================

module modular_multiplier_256bit #(
    parameter WIDTH = 256,      // 位宽参数，默认256位
    parameter PIPELINE_STAGES = 4  // 蒙哥马利乘法器流水线级数
) (
    input wire                     clk,
    input wire                     rst_n,
    input wire                     start,
    input wire  [WIDTH-1:0]        a,
    input wire  [WIDTH-1:0]        b,
    input wire  [WIDTH-1:0]        N,
    input wire  [WIDTH-1:0]        Np,
    input wire  [WIDTH-1:0]        R2_mod_N,
    
    output reg  [WIDTH-1:0]        result,
    output reg                     done,
    output reg                     busy
);

// ============================================================================
// Local Parameters and Registers
// ============================================================================
localparam [3:0]
    S_IDLE        = 4'd0,
    S_SETUP_A     = 4'd1,  // 设置A转换的输入
    S_CONV_A      = 4'd2,  // 执行A转换
    S_WAIT_A      = 4'd3,  // 等待A转换完成
    S_SETUP_B     = 4'd4,  // 设置B转换的输入
    S_CONV_B      = 4'd5,  // 执行B转换
    S_WAIT_B      = 4'd6,  // 等待B转换完成
    S_SETUP_MUL   = 4'd7,  // 设置乘法的输入
    S_CONV_MUL    = 4'd8,  // 执行乘法
    S_WAIT_MUL    = 4'd9,  // 等待乘法完成
    S_SETUP_OUT   = 4'd10, // 设置输出转换的输入
    S_CONV_OUT    = 4'd11, // 执行输出转换
    S_WAIT_OUT    = 4'd12, // 等待输出转换完成
    S_DONE        = 4'd13;

reg [3:0] state;
reg [WIDTH-1:0] a_reg, b_reg;
reg [WIDTH-1:0] a_mont, b_mont;
reg [WIDTH-1:0] temp_result;

// Montgomery multiplier control signals
reg mont_start;
wire mont_done;
wire [WIDTH-1:0] mont_result;

// ============================================================================
// Parameterized Montgomery Multiplier Instance
// ============================================================================
montgomery_multiplier_256bit #(
    .TOTAL_BITS(WIDTH),
    .SEG_BITS(64)
) mul_inst(
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
// Complete State Machine with All States
// ============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= S_IDLE;
        done <= 1'b0;
        busy <= 1'b0;
        a_mont <= {WIDTH{1'b0}};
        b_mont <= {WIDTH{1'b0}};
        result <= {WIDTH{1'b0}};
        mont_start <= 1'b0;
        temp_result <= {WIDTH{1'b0}};
        a_reg <= {WIDTH{1'b0}};
        b_reg <= {WIDTH{1'b0}};
    end else begin
        // 默认不启动乘法器
        mont_start <= 1'b0;
        
        case (state)
            S_IDLE: begin
                done <= 1'b0;
                busy <= 1'b0;
                if (start) begin
                    busy <= 1'b1;
                    // 设置A转换的输入
                    a_reg <= a;          // 普通域的a
                    b_reg <= R2_mod_N;   // R^2 mod N
                    state <= S_SETUP_A;
                end
            end
            
            S_SETUP_A: begin
                // 等待一个周期，确保输入稳定
                state <= S_CONV_A;
            end
            
            S_CONV_A: begin
                // 启动A转换
                mont_start <= 1'b1;
                state <= S_WAIT_A;
            end
            
            S_WAIT_A: begin
                // 等待转换完成
                if (mont_done) begin
                    // 捕获A的转换结果
                    a_mont <= mont_result;
                    
                    // 设置B转换的输入
                    a_reg <= b;          // 普通域的b
                    b_reg <= R2_mod_N;   // R^2 mod N
                    state <= S_SETUP_B;
                end
            end
            
            S_SETUP_B: begin
                // 等待一个周期，确保输入稳定
                state <= S_CONV_B;
            end
            
            S_CONV_B: begin
                // 启动B转换
                mont_start <= 1'b1;
                state <= S_WAIT_B;
            end
            
            S_WAIT_B: begin
                // 等待转换完成
                if (mont_done) begin
                    // 捕获B的转换结果
                    b_mont <= mont_result;
                    
                    // 设置乘法的输入
                    a_reg <= a_mont;
                    b_reg <= b_mont;
                    state <= S_SETUP_MUL;
                end
            end
            
            S_SETUP_MUL: begin
                // 等待一个周期，确保输入稳定
                state <= S_CONV_MUL;
            end
            
            S_CONV_MUL: begin
                // 启动乘法
                mont_start <= 1'b1;
                state <= S_WAIT_MUL;
            end
            
            S_WAIT_MUL: begin
                // 等待乘法完成
                if (mont_done) begin
                    // 捕获乘法结果
                    temp_result <= mont_result;
                    
                    // 设置输出转换的输入
                    a_reg <= temp_result;
                    b_reg <= {{(WIDTH-1){1'b0}}, 1'b1};  // 乘以1回到普通域
                    state <= S_SETUP_OUT;
                end
            end
            
            S_SETUP_OUT: begin
                // 等待一个周期，确保输入稳定
                state <= S_CONV_OUT;
            end
            
            S_CONV_OUT: begin
                // 启动输出转换
                mont_start <= 1'b1;
                state <= S_WAIT_OUT;
            end
            
            S_WAIT_OUT: begin
                // 等待输出转换完成
                if (mont_done) begin
                    // 捕获最终结果
                    result <= mont_result;
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
