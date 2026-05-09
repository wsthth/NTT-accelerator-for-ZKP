// ============================================================================
// 文件名: montgomery_top.v
// 描述: 修正的顶层模块，适配512位t输入
// ============================================================================
`timescale 1ns/1ps

module montgomery_top(
    // 仅4个核心引脚
    input  wire        clk,       // 100MHz系统时钟
    input  wire        rst_n,     // 低电平复位
    input  wire        start,     // 实验启动信号
    output reg         done       // 实验完成指示
);

// ============================================================================
// 参数定义 (使用BN254曲线参数)
// ============================================================================
localparam TOTAL_BITS = 256;
localparam SEG_BITS = 64;
localparam SEG_CNT = TOTAL_BITS / SEG_BITS;

// BN254模数 (256位)
localparam [TOTAL_BITS-1:0] N = 256'h30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47;

// 预计算的 N' = -N^(-1) mod R (256位)
// 注意：这个值需要根据实际计算得到，以下是示例值
localparam [TOTAL_BITS-1:0] N_prime = 256'hf57a22b791888c6bd8afcbd01833da809ede7d651eca6ac987d20782e4866389;

// ============================================================================
// 内部测试向量 (512位t值)
// ============================================================================
// 这些值应该从Python验证脚本生成
// 这里使用示例值，实际使用时需要替换为真实值

// a_mont = a * R mod N (256位)
localparam [TOTAL_BITS-1:0] A_MONT = 256'h16db3787c008bbc00870a59497036f7f43e71fc1218341741c7bc7cc0ceb3313;
// localparam [TOTAL_BITS-1:0] A_MONT = 256'h71937286f35f09d10368c1841047b48f948bf8edabc2ce29e9e0528e4e19413;


// b_mont = b * R mod N (256位)  
localparam [TOTAL_BITS-1:0] B_MONT = 256'h87a1d2b7448c77d0c5a8c4e7241aa9a40f3f294768bdd2611e3d89374ff16f6;
// localparam [TOTAL_BITS-1:0] B_MONT = 256'h25fb03b940617d15f2a74e89bfe348bb62020133408b6c99aed5e4fe8f9d2348;


// t = a_mont * b_mont (512位)
// 注意：这个值是a_mont和b_mont的乘积，需要从Python脚本计算得到
// 这里使用一个示例值，实际需要正确计算
localparam [2*TOTAL_BITS-1:0] T_512 = 512'hc1c0cf6b3053366c04cc5be157a618a4b05dc32dbba48398976daccbcd6a4bf7692fac951ce65ecc6b353dff255768a7b9b946411649b0e73854861c53b642;

// localparam [2*TOTAL_BITS-1:0] T_512 = 512'h10d9acc5b5f2cff8afdde66d2d79eb05306f571ee8d01e5b47d1c9be023c9a51c2fb3a724fe0b2924ebf26b0a3f40a9ba32fdf2ac38f753569541b3a3573e58;


// 预期结果 (256位)
// 这个值应该是 (a * b) mod N，需要从Python脚本计算得到
localparam [TOTAL_BITS-1:0] EXPECTED_RESULT = 256'h1c4d8e1b9f8a3d2c5b6a7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9;

// ============================================================================
// 内部信号
// ============================================================================
wire [TOTAL_BITS-1:0] mont_result;
wire mont_valid;
wire mont_done;

reg [31:0] test_counter;
reg internal_start;
reg [TOTAL_BITS-1:0] result_reg;
reg result_valid;
reg error_detected;
reg [TOTAL_BITS-1:0] error_expected;





// ============================================================================
// 蒙哥马利模约简模块实例化
// 注意：t的位宽现在是512位
// ============================================================================
montgomery_pipeline #(
    .TOTAL_BITS(TOTAL_BITS),
    .SEG_BITS(SEG_BITS),
    .SEG_CNT(SEG_CNT),
    .PIPELINE_STAGES(4)
) u_montgomery (
    .clk(clk),
    .rst_n(rst_n),
    .start(internal_start),
    .N(N),
    .N_prime(N_prime),
    .t(T_512),                    // 传入512位的t值
    .mont_result(mont_result),    // 输出256位结果
    .valid_out(mont_valid),
    .done(mont_done)
);

// ============================================================================
// 控制逻辑
// ============================================================================
reg [2:0] state;
localparam S_IDLE   = 3'b000;
localparam S_START  = 3'b001;
localparam S_WAIT   = 3'b010;
localparam S_CHECK  = 3'b011;
localparam S_DONE   = 3'b100;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= S_IDLE;
        internal_start <= 1'b0;
        test_counter <= 32'd0;
        result_reg <= {TOTAL_BITS{1'b0}};
        result_valid <= 1'b0;
        done <= 1'b0;
        error_detected <= 1'b0;
        error_expected <= {TOTAL_BITS{1'b0}};
    end else begin
        case (state)
            S_IDLE: begin
                internal_start <= 1'b0;
                result_valid <= 1'b0;
                done <= 1'b0;
                if (start) begin
                    state <= S_START;
                    test_counter <= 32'd0;
                    $display("[TOP] 检测到启动信号");
                end
            end
            
            S_START: begin
                internal_start <= 1'b1;
                state <= S_WAIT;
                test_counter <= 32'd1;
                $display("[TOP] 启动蒙哥马利计算");
                $display("[TOP] t = 0x%h... (512位)", T_512);
                $display("[TOP] N = 0x%h", N);
                $display("[TOP] N_prime = 0x%h", N_prime);
            end
            
            S_WAIT: begin
                internal_start <= 1'b0;
                
                if (mont_done) begin
                    result_reg <= mont_result;
                    result_valid <= 1'b1;
                    state <= S_CHECK;
                    test_counter <= 32'd0;
                    $display("[TOP] 蒙哥马利计算完成");
                    $display("[TOP] 计算结果: 0x%h", mont_result);
                end else if (test_counter > 32'd100) begin
                    // 超时保护
                    $display("[TOP] 超时错误!");
                    state <= S_IDLE;
                end else begin
                    test_counter <= test_counter + 1;
                end
            end
            
            S_CHECK: begin
                // 验证结果是否正确
                if (result_reg == EXPECTED_RESULT) begin
                    error_detected <= 1'b0;
                    $display("[TOP] ✅ 验证通过!");
                end else begin
                    error_detected <= 1'b1;
                    $display("[TOP] ❌ 验证失败!");
                    $display("[TOP] 预期结果: 0x%h", EXPECTED_RESULT);
                    $display("[TOP] 实际结果: 0x%h", result_reg);
                end
                
                error_expected <= EXPECTED_RESULT;
                state <= S_DONE;
                test_counter <= 32'd0;
            end
            
            S_DONE: begin
                // 置位done信号
                done <= 1'b1;
                
                // 保持done信号一段时间，然后回到空闲状态
                if (test_counter > 32'd20) begin
                    state <= S_IDLE;
                    done <= 1'b0;
                end else begin
                    test_counter <= test_counter + 1;
                end
            end
            
            default: begin
                state <= S_IDLE;
            end
        endcase
    end
end

/* // ============================================================================
// 调试输出 (仅用于仿真)
// ============================================================================
// synthesis translate_off
reg [31:0] cycle_count;

initial begin
    cycle_count = 0;
end

always @(posedge clk) begin
    if (!rst_n) begin
        cycle_count <= 0;
    end else begin
        cycle_count <= cycle_count + 1;
        
        // 显示状态变化
        if (state == S_START) begin
            $display("[TOP] Cycle %0d: 状态 -> START", cycle_count);
        end else if (state == S_WAIT) begin
            if (mont_valid) begin
                $display("[TOP] Cycle %0d: 蒙哥马利模块输出有效", cycle_count);
            end
        end else if (state == S_CHECK) begin
            $display("[TOP] Cycle %0d: 状态 -> CHECK", cycle_count);
        end else if (state == S_DONE) begin
            if (test_counter == 0) begin
                $display("[TOP] Cycle %0d: 状态 -> DONE", cycle_count);
            end
        end
    end
end

// 显示关键参数
initial begin
    #10;
    $display("\n[TOP] ===========================================");
    $display("[TOP] 蒙哥马利模约简测试参数");
    $display("[TOP] ===========================================");
    $display("[TOP] 模数 N: 0x%h", N);
    $display("[TOP] N_prime: 0x%h", N_prime);
    $display("[TOP] a_mont: 0x%h", A_MONT);
    $display("[TOP] b_mont: 0x%h", B_MONT);
    $display("[TOP] t (512位): 0x%h...", T_512);
    $display("[TOP] 预期结果: 0x%h", EXPECTED_RESULT);
    $display("[TOP] ===========================================\n");
end
// synthesis translate_on
 */



endmodule

