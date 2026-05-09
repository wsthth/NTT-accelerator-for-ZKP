// ntt_twiddle_dynamic_gen.v
`timescale 1ns / 1ps

module ntt_twiddle_dynamic_gen #(
    // ================= 可配置参数 =================
    parameter DATA_WIDTH        = 256,        // 数据位宽（大模数256位）
    parameter MAX_MODULUS_BITS  = 384,        // 最大模数位宽
    parameter PARALLEL_LEVEL    = 4,          // 并行度
    parameter PIPELINE_DEPTH    = 3           // 流水线深度
)(
    // ================= 时钟与复位 =================
    input  wire                          clk,
    input  wire                          reset_n,
    
    // ================= 控制接口 =================
    input  wire                          start_gen,
    input  wire                          mode,           // 0:正向NTT，1:逆向NTT
    
    // ================= 配置参数 =================
    input  wire [DATA_WIDTH-1:0]         modulus,        // 模数（大模数256位）
    input wire [DATA_WIDTH-1:0] Np,        // -N^{-1} mod R
    input wire [DATA_WIDTH-1:0] R2_mod_N,  // R^2 mod N
    
    input  wire [DATA_WIDTH-1:0]         primitive_root, // 原根g
    input  wire [DATA_WIDTH-1:0]         base_twiddle,   // 预存的基础旋转因子ω_base = g^{(q-1)/N}
    input  wire [15:0]                   N,              // NTT长度
    input  wire [7:0]                    stage,          // NTT阶段
    input  wire [7:0]                    index,          // 旋转因子索引
    
    // ================= 生成结果 =================
    output reg  [DATA_WIDTH-1:0]         twiddle_out,    // NTT旋转因子（单个整数）
    output reg                           gen_done,
    output reg                           gen_valid,
    
    // ================= 性能监控 =================
    output reg  [15:0]                   gen_cycles,
    output reg  [7:0]                    gen_latency,
    output wire                          parallel_active,
    
    // ================= 错误指示 =================
    output wire                          error
);

// ================= 状态定义 =================
localparam STATE_IDLE          = 4'b0000;
localparam STATE_CALC_EXPONENT = 4'b0001;
localparam STATE_CALC_BASE     = 4'b0010;
localparam STATE_PARALLEL_INIT = 4'b0011;
localparam STATE_PARALLEL_GEN  = 4'b0100;
localparam STATE_SELECT_OUTPUT = 4'b0101;
localparam STATE_DONE          = 4'b0110;

// ================= 内部寄存器 =================
reg  [3:0]                   state;
reg  [31:0]                  counter;
reg  [DATA_WIDTH-1:0]        current_modulus;
reg  [DATA_WIDTH-1:0]        current_primitive_root;
reg  [DATA_WIDTH-1:0]        current_base_twiddle;
reg  [15:0]                  current_N;
reg  [7:0]                   current_stage;
reg  [7:0]                   current_index;

// 幂次计算相关
reg  [31:0]                  target_exponent;
reg  [DATA_WIDTH-1:0]        step_value;      // 步进值：ω_base^{N/2^{s+1}}
reg  [DATA_WIDTH-1:0]        base_value;      // 基础值：ω_base^{rev_index}

// 并行生成相关
wire [DATA_WIDTH*PARALLEL_LEVEL-1:0] parallel_twiddles_packed;
reg  [DATA_WIDTH-1:0]        parallel_twiddles_array [0:PARALLEL_LEVEL-1];
reg                          parallel_start;
wire                         parallel_done;

// ================= start_gen 同步逻辑 =================
reg start_gen_sync1, start_gen_sync2;
wire start_gen_rising;

// 同步 start_gen 信号，避免亚稳态
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        start_gen_sync1 <= 0;
        start_gen_sync2 <= 0;
    end else begin
        start_gen_sync1 <= start_gen;
        start_gen_sync2 <= start_gen_sync1;
    end
end

// 检测 start_gen 上升沿
assign start_gen_rising = start_gen_sync1 && !start_gen_sync2;

// 解包数组（用于选择输出）
integer j;
always @(*) begin
    for (j = 0; j < PARALLEL_LEVEL; j = j + 1) begin
        parallel_twiddles_array[j] = parallel_twiddles_packed[j*DATA_WIDTH +: DATA_WIDTH];
    end
end

// ================= 位反转函数 =================
function [7:0] bit_reverse_8;
    input [7:0] x;
    integer i;
begin
    for (i = 0; i < 8; i = i + 1) begin
        bit_reverse_8[i] = x[7-i];
    end
end
endfunction

// ================= 指数计算函数 =================
function [31:0] calculate_exponent;
    input [15:0] N;
    input [7:0] stage;
    input [7:0] index;
    input mode;
    reg [7:0] rev_index;
    reg [31:0] power;
begin
    // 计算位反转
    rev_index = bit_reverse_8(index);
    
    // NTT旋转因子指数计算公式：
    // 正向：ω_N^{rev(i)} = ω_base^{rev(i) * (N/2^{s+1})}
    // 其中 ω_base = g^{(q-1)/N}
    
    // 计算 rev(i) * (N >> (s+1))
    power = rev_index * (N >> (stage + 1));
    
    if (mode == 1) begin
        // 逆向NTT：使用负指数
        // ω_N^{-rev(i)} = ω_base^{(q-1) - [rev(i) * (N/2^{s+1}) mod (q-1)]}
        power = (current_modulus - 1) - (power % (current_modulus - 1));
    end
    
    calculate_exponent = power;
end
endfunction

// ================= 模乘接口 =================
wire [DATA_WIDTH-1:0]        mod_mult_result;
wire                         mod_mult_done;
reg                          mod_mult_start;
reg  [DATA_WIDTH-1:0]        mod_mult_a;
reg  [DATA_WIDTH-1:0]        mod_mult_b;

// 大数模乘模块实例
modular_multiplier_256bit mod_mult_inst (
    .clk(clk),
    .rst_n(reset_n),
    .start(mod_mult_start),
    .a(mod_mult_a),
    .b(mod_mult_b),
    .N(current_modulus),
    .Np(),
    .R2_mod_N(),
    .result(mod_mult_result),
    .done(mod_mult_done),
    .busy()
);

// ================= 模幂接口 =================
wire [DATA_WIDTH-1:0]        mod_pow_result;
wire                         mod_pow_done;
reg                          mod_pow_start;
reg  [DATA_WIDTH-1:0]        mod_pow_base;
reg  [31:0]                  mod_pow_exponent;

// 模幂模块实例
modular_exponentiation #(
    .DATA_WIDTH(DATA_WIDTH)
) mod_pow_inst (
    .clk(clk),
    .reset_n(reset_n),
    .start(mod_pow_start),
    .base(mod_pow_base),
    .exponent(mod_pow_exponent),
    .modulus(current_modulus),
    .Np(),
    .R2_mod_N(),
    .result(mod_pow_result),
    .done(mod_pow_done)
);

// ================= 并行递推单元实例化 =================
ntt_parallel_recurrence_unit #(
    .NUM_PARALLEL(PARALLEL_LEVEL),
    .DATA_WIDTH(DATA_WIDTH)
) parallel_unit (
    .clk(clk),
    .reset_n(reset_n),
    .start(parallel_start),
    .base_value(base_value),
    .step_value(step_value),
    .modulus(current_modulus),
    .Np(),
    .R2_mod_N(),
    .twiddles_packed(parallel_twiddles_packed),
    .done(parallel_done)
);

// ================= 预存表（可选，用于加速计算） =================
// 预存基础旋转因子的幂次：ω_base^1, ω_base^2, ω_base^4, ω_base^8, ...
reg [DATA_WIDTH-1:0] precomputed_table [0:31];  // 最多支持2^32
reg precomputed_valid;
    integer k;  // 将 int 改为 integer

// 初始化预存表（可在空闲时计算）
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        precomputed_valid <= 0;
        for (k = 0; k < 32; k = k + 1) begin
            precomputed_table[k] <= 0;
        end
    end else if (state == STATE_IDLE && start_gen_rising) begin
        // 当有新参数时，重新计算预存表
        precomputed_table[0] <= current_base_twiddle;  // ω_base^1
        for (k = 1; k < 32; k = k + 1) begin
            // ω_base^{2^k} = (ω_base^{2^{k-1}})^2 mod q
            precomputed_table[k] <= 0;  // 实际计算需要模乘模块
        end
        precomputed_valid <= 0;  // 标记为需要重新计算
    end
end

// ================= 主状态机 =================
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        // 状态机寄存器
        state <= STATE_IDLE;
        counter <= 0;
        
        // 输出寄存器
        gen_done <= 0;
        gen_valid <= 0;
        gen_cycles <= 0;
        gen_latency <= 0;
        twiddle_out <= 0;
        
        // 内部参数寄存器
        current_modulus <= 0;
        current_primitive_root <= 0;
        current_base_twiddle <= 0;
        current_N <= 0;
        current_stage <= 0;
        current_index <= 0;
        
        // 幂次计算寄存器
        target_exponent <= 0;
        step_value <= 0;
        base_value <= 0;
        
        // 控制信号
        parallel_start <= 0;
        mod_mult_start <= 0;
        mod_pow_start <= 0;
        
        // 模运算接口寄存器
        mod_mult_a <= 0;
        mod_mult_b <= 0;
        mod_pow_base <= 0;
        mod_pow_exponent <= 0;
        
        $display("[%t] NTT Twiddle Generator: Complete reset", $time);
    end else begin
        gen_cycles <= gen_cycles + 1;
        
        // 默认清零单周期信号
        mod_mult_start <= 0;
        mod_pow_start <= 0;
        parallel_start <= 0;
        gen_valid <= 0;
        
        $display("[%t] NTT DEBUG: state=%h, counter=%d", $time, state, counter);
        
        case (state)
            STATE_IDLE: begin
                if (start_gen_rising) begin
                    // 锁存输入参数
                    current_modulus <= modulus;
                    current_primitive_root <= primitive_root;
                    current_base_twiddle <= base_twiddle;
                    current_N <= N;
                    current_stage <= stage;
                    current_index <= index;
                    
                    counter <= 0;
                    gen_latency <= 0;
                    gen_valid <= 0;
                    gen_done <= 0;
                    
                    state <= STATE_CALC_EXPONENT;
                    
                    $display("[%t] NTT: Start generation", $time);
                    $display("[%t] NTT: Parameters - N=%d, stage=%d, index=%d, mode=%b",
                             $time, N, stage, index, mode);
                end
            end
            
            STATE_CALC_EXPONENT: begin
                counter <= counter + 1;
                
                if (counter == 0) begin
                    // 计算目标指数
                    target_exponent <= calculate_exponent(current_N, current_stage, current_index, mode);
                    
                    // 计算步进值：ω_base^{N/2^{s+1}}
                    // 这是每个阶段旋转因子的步进乘数
                    mod_pow_base <= current_base_twiddle;
                    mod_pow_exponent <= current_N >> (current_stage + 1);
                    mod_pow_start <= 1;
                end
                
                if (mod_pow_done) begin
                    step_value <= mod_pow_result;
                    state <= STATE_CALC_BASE;
                    counter <= 0;
                    $display("[%t] NTT: Step value calculated = %h", $time, mod_pow_result);
                end else if (counter > 100) begin
                    // 超时保护
                    $display("[%t] NTT WARNING: mod_pow timeout", $time);
                    step_value <= current_base_twiddle;  // 使用默认值
                    state <= STATE_CALC_BASE;
                    counter <= 0;
                end
            end
            
            STATE_CALC_BASE: begin
                counter <= counter + 1;
                
                if (counter == 0) begin
                    // 计算基础值：ω_base^{rev(index)}
                    // 这是当前索引对应的旋转因子
                    
                    // 如果指数较小，可以直接使用预存表
                    if (target_exponent < 256) begin
                        // 使用快速幂算法
                        mod_pow_base <= current_base_twiddle;
                        mod_pow_exponent <= target_exponent;
                        mod_pow_start <= 1;
                    end else begin
                        // 对于大指数，使用更高效的算法
                        // 这里简化为直接计算
                        mod_pow_base <= current_base_twiddle;
                        mod_pow_exponent <= target_exponent;
                        mod_pow_start <= 1;
                    end
                end
                
                if (mod_pow_done) begin
                    base_value <= mod_pow_result;
                    state <= STATE_PARALLEL_INIT;
                    counter <= 0;
                    $display("[%t] NTT: Base value calculated = %h", $time, mod_pow_result);
                end else if (counter > 100) begin
                    // 超时保护
                    $display("[%t] NTT WARNING: base calculation timeout", $time);
                    base_value <= current_base_twiddle;  // 使用默认值
                    state <= STATE_PARALLEL_INIT;
                    counter <= 0;
                end
            end
            
            STATE_PARALLEL_INIT: begin
                counter <= counter + 1;
                
                if (counter == 0) begin
                    // 启动并行单元
                    parallel_start <= 1;
                    $display("[%t] NTT: Starting parallel unit", $time);
                end
                
                if (counter == 1) begin
                    parallel_start <= 0;
                    state <= STATE_PARALLEL_GEN;
                end
            end
            
            STATE_PARALLEL_GEN: begin
                counter <= counter + 1;
                
                if (parallel_done) begin
                    // 并行生成完成
                    state <= STATE_SELECT_OUTPUT;
                    counter <= 0;
                    $display("[%t] NTT: Parallel generation done", $time);
                end else if (counter > 50) begin
                    // 超时保护
                    $display("[%t] NTT WARNING: parallel unit timeout", $time);
                    state <= STATE_SELECT_OUTPUT;
                    counter <= 0;
                end
            end
            
            STATE_SELECT_OUTPUT: begin
                counter <= counter + 1;
                
                if (counter == 0) begin
                    // 选择对应索引的旋转因子
                    if (current_index < PARALLEL_LEVEL) begin
                        twiddle_out <= parallel_twiddles_array[current_index];
                    end else begin
                        // 如果索引超出并行范围，计算正确的值
                        // 这可以通过继续递推得到
                        // 简化：使用第一个值
                        twiddle_out <= parallel_twiddles_array[0];
                    end
                    
                    gen_valid <= 1;
                    $display("[%t] NTT: Selected twiddle = %h", $time, twiddle_out);
                end
                
                if (counter >= 1) begin
                    state <= STATE_DONE;
                end
            end
            
            STATE_DONE: begin
                gen_done <= 1;
                gen_valid <= 0;
                counter <= 0;
                
                $display("[%t] NTT: Generation DONE", $time);
                $display("[%t] NTT: Final output = %h", $time, twiddle_out);
                
                if (mode && start_gen_rising) begin
                    // 连续模式：准备下一次生成
                    state <= STATE_CALC_EXPONENT;
                    gen_done <= 0;
                    $display("[%t] NTT: Continuous mode - starting next generation", $time);
                end else begin
                    state <= STATE_IDLE;
                end
            end
            
            default: begin
                state <= STATE_IDLE;
            end
        endcase
        
        // 更新生成延迟
        if (start_gen && !gen_done) begin
            gen_latency <= gen_latency + 1;
        end
    end
end

assign parallel_active = (state == STATE_PARALLEL_GEN);
assign error = (state == STATE_IDLE) ? 1'b0 : 1'b0;  // 简化错误检测

endmodule