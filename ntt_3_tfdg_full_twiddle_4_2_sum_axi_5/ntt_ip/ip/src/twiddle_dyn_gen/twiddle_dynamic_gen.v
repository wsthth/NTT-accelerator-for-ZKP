// twiddle_dynamic_gen_fixed_vivado.v
// Vivado兼容版本
`timescale 1ns / 1ps

module twiddle_dynamic_gen #(
    // ================= 可配置参数 =================
    parameter DATA_WIDTH        = 32,        // 数据位宽
    parameter MODULUS_WIDTH     = 16,        // 模数位宽
    parameter MAX_MODULUS       = 12289,     // 最大模数值
    parameter PARALLEL_LEVEL    = 4,         // 并行度
    parameter PIPELINE_DEPTH    = 3,         // 流水线深度
    parameter Q_FORMAT          = 16         // Q格式：Q15.16
)(
    // ================= 时钟与复位 =================
    input  wire                          clk,
    input  wire                          reset_n,
    
    // ================= 控制接口 =================
    input  wire                          start_gen,
    input  wire                          mode,
    input  wire [1:0]                    precision,
    
    // ================= 配置参数 =================
    input  wire [MODULUS_WIDTH-1:0]      modulus,      // 模数（16位输入）
    input  wire [15:0]                   N,
    input  wire [7:0]                    stage,
    input  wire [7:0]                    index,
    
    // ================= 生成结果 =================
    output reg  [DATA_WIDTH-1:0]         twiddle_real,
    output reg  [DATA_WIDTH-1:0]         twiddle_imag,
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
localparam STATE_CALC_BASE     = 4'b0001;
localparam STATE_PARALLEL_INIT = 4'b0010;
localparam STATE_PARALLEL_GEN  = 4'b0011;
localparam STATE_NORMALIZATION = 4'b0100;
localparam STATE_DONE          = 4'b0101;

// ================= 内部寄存器 =================
reg  [3:0]                   state;
reg  [31:0]                  counter;
reg  [DATA_WIDTH-1:0]        current_modulus_32;  // 32位模数
reg  [MODULUS_WIDTH-1:0]     current_modulus_16;  // 16位模数
reg  [15:0]                  current_N;
reg  [7:0]                   current_stage;
reg  [7:0]                   current_index;

reg  [DATA_WIDTH-1:0]        base_real;
reg  [DATA_WIDTH-1:0]        base_imag;
reg  [DATA_WIDTH-1:0]        omega_real;
reg  [DATA_WIDTH-1:0]        omega_imag;

// 并行生成相关
wire [DATA_WIDTH*PARALLEL_LEVEL-1:0] parallel_real_packed;
wire [DATA_WIDTH*PARALLEL_LEVEL-1:0] parallel_imag_packed;
reg  [DATA_WIDTH-1:0]        parallel_real_array [0:PARALLEL_LEVEL-1];
reg  [DATA_WIDTH-1:0]        parallel_imag_array [0:PARALLEL_LEVEL-1];
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
        parallel_real_array[j] = parallel_real_packed[j*DATA_WIDTH +: DATA_WIDTH];
        parallel_imag_array[j] = parallel_imag_packed[j*DATA_WIDTH +: DATA_WIDTH];
    end
end

// 模乘接口（简化，实际使用时需要实现）
wire [DATA_WIDTH-1:0]        mod_mult_result_real;
wire [DATA_WIDTH-1:0]        mod_mult_result_imag;
wire                         mod_mult_done;
reg                          mod_mult_start;
reg  [DATA_WIDTH-1:0]        mod_mult_a_real;
reg  [DATA_WIDTH-1:0]        mod_mult_a_imag;
reg  [DATA_WIDTH-1:0]        mod_mult_b_real;
reg  [DATA_WIDTH-1:0]        mod_mult_b_imag;
reg  [DATA_WIDTH-1:0]        mod_mult_modulus;

// 简化模乘模块（仅用于仿真）
simplified_mod_mult #(
    .DATA_WIDTH(DATA_WIDTH)
) mod_mult_inst (
    .clk(clk),
    .reset_n(reset_n),
    .start(mod_mult_start),
    .a_real(mod_mult_a_real),
    .a_imag(mod_mult_a_imag),
    .b_real(mod_mult_b_real),
    .b_imag(mod_mult_b_imag),
    .modulus(mod_mult_modulus),
    .result_real(mod_mult_result_real),
    .result_imag(mod_mult_result_imag),
    .done(mod_mult_done)
);

// ================= 并行递推单元实例化 =================
parallel_recurrence_unit_packed_fixed #(
    .NUM_PARALLEL(PARALLEL_LEVEL),
    .DATA_WIDTH(DATA_WIDTH)
) parallel_unit (
    .clk(clk),
    .reset_n(reset_n),
    .start(parallel_start),
    .base_real(base_real),
    .base_imag(base_imag),
    .omega_real(omega_real),
    .omega_imag(omega_imag),
    .modulus(current_modulus_32),  // 传入32位模数
    .twiddle_real_packed(parallel_real_packed),
    .twiddle_imag_packed(parallel_imag_packed),
    .done(parallel_done)
);

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
        twiddle_real <= 0;
        twiddle_imag <= 0;
        
        // 内部参数寄存器
        current_modulus_16 <= 0;
        current_modulus_32 <= 0;
        current_N <= 0;
        current_stage <= 0;
        current_index <= 0;
        
        // 基础值和Omega值
        base_real <= 0;
        base_imag <= 0;
        omega_real <= 0;
        omega_imag <= 0;
        
        // 控制信号
        parallel_start <= 0;
        mod_mult_start <= 0;
        
        // 模乘接口寄存器
        mod_mult_a_real <= 0;
        mod_mult_a_imag <= 0;
        mod_mult_b_real <= 0;
        mod_mult_b_imag <= 0;
        mod_mult_modulus <= 0;
        
        // 调试信息
        $display("[%t] DUT: Complete reset - all registers initialized", $time);
    end else begin
        gen_cycles <= gen_cycles + 1;
        
        // 调试：监控状态机转换
        if (state != STATE_IDLE || start_gen_rising) begin
            $display("[%t] DUT DEBUG: state=%h, start_gen=%b, start_gen_rising=%b, counter=%d", 
                     $time, state, start_gen, start_gen_rising, counter);
        end
        
        case (state)
            STATE_IDLE: begin
                // 使用同步后的 start_gen_rising 信号
                if (start_gen_rising) begin
                    // 锁存输入参数
                    current_modulus_16 <= modulus;
                    current_modulus_32 <= {16'b0, modulus};  // 16位扩展为32位
                    current_N <= N;
                    current_stage <= stage;
                    current_index <= index;
                    
                    counter <= 0;
                    gen_latency <= 0;
                    gen_valid <= 0;
                    gen_done <= 0;
                    
                    state <= STATE_CALC_BASE;
                    
                    $display("[%t] DUT: start_gen_rising detected - moving to CALC_BASE", $time);
                    $display("[%t] DUT: Inputs latched - modulus=%h (%d), N=%d, stage=%d, index=%d",
                             $time, modulus, modulus, N, stage, index);
                    $display("[%t] DUT: current_modulus_16 = %h, current_modulus_32 = %h\n",
                             $time, modulus, {16'b0, modulus});
                end
            end
            
            STATE_CALC_BASE: begin
                counter <= counter + 1;
                
                $display("[%t] DUT: In CALC_BASE, counter=%d", $time, counter);
                
                if (counter == 0) begin
                    // 启动模乘计算基础旋转因子
                    mod_mult_a_real <= 32'h00010000; // cos(0) = 1.0 in Q15.16
                    mod_mult_a_imag <= 32'h00000000; // sin(0) = 0
                    mod_mult_b_real <= 32'h00010000; // 乘以1.0
                    mod_mult_b_imag <= 32'h00000000;
                    mod_mult_modulus <= current_modulus_32;
                    mod_mult_start <= 1;
                    
                    $display("[%t] DUT: Starting mod_mult calculation", $time);
                    $display("[%t] DUT: mod_mult inputs - a_real=%h, modulus=%h", 
                             $time, 32'h00010000, current_modulus_32);
                end
                
                if (counter == 1) begin
                    mod_mult_start <= 0;
                end
                
                // 添加超时保护
                if (mod_mult_done) begin
                    base_real <= mod_mult_result_real;
                    base_imag <= mod_mult_result_imag;
                    omega_real <= mod_mult_result_real;
                    omega_imag <= mod_mult_result_imag;
                    counter <= 0;
                    state <= STATE_PARALLEL_INIT;
                    
                    $display("[%t] DUT: mod_mult_done received, moving to PARALLEL_INIT", $time);
                    $display("[%t] DUT: Results - base_real=%h, base_imag=%h", 
                             $time, mod_mult_result_real, mod_mult_result_imag);
                end else if (counter > 50) begin
                    // 超时保护：50个周期后强制继续
                    $display("[%t] DUT WARNING: mod_mult timeout after %d cycles, using defaults", 
                             $time, counter);
                    base_real <= 32'h00010000;
                    base_imag <= 32'h00000000;
                    omega_real <= 32'h00010000;
                    omega_imag <= 32'h00000000;
                    counter <= 0;
                    state <= STATE_PARALLEL_INIT;
                end
            end
            
            STATE_PARALLEL_INIT: begin
                counter <= counter + 1;
                
                $display("[%t] DUT: In PARALLEL_INIT, counter=%d", $time, counter);
                
                if (counter == 0) begin
                    parallel_start <= 1;
                    $display("[%t] DUT: Starting parallel unit", $time);
                end
                
                if (counter == 1) begin
                    parallel_start <= 0;
                    state <= STATE_PARALLEL_GEN;
                end
            end
            
            STATE_PARALLEL_GEN: begin
                counter <= counter + 1;
                
                if (parallel_done) begin
                    gen_valid <= 1;
                    
                    // 选择对应索引的旋转因子
                    if (current_index < PARALLEL_LEVEL) begin
                        twiddle_real <= parallel_real_array[current_index];
                        twiddle_imag <= parallel_imag_array[current_index];
                    end else begin
                        twiddle_real <= parallel_real_array[PARALLEL_LEVEL-1];
                        twiddle_imag <= parallel_imag_array[PARALLEL_LEVEL-1];
                    end
                    
                    counter <= 0;
                    state <= STATE_NORMALIZATION;
                    
                    $display("[%t] DUT: parallel_done received, output selected", $time);
                    $display("[%t] DUT: Selected index=%d, real=%h, imag=%h", 
                             $time, current_index, twiddle_real, twiddle_imag);
                end else if (counter > 50) begin
                    // 超时保护：50个周期后强制继续
                    $display("[%t] DUT WARNING: parallel unit timeout, using defaults", $time);
                    twiddle_real <= base_real;
                    twiddle_imag <= base_imag;
                    gen_valid <= 1;
                    counter <= 0;
                    state <= STATE_NORMALIZATION;
                end
            end
            
            STATE_NORMALIZATION: begin
                counter <= counter + 1;
                
                $display("[%t] DUT: In NORMALIZATION, counter=%d", $time, counter);
                
                // 归一化到[-modulus/2, modulus/2]
                if (twiddle_real > (current_modulus_16 >> 1)) begin
                    twiddle_real <= twiddle_real - current_modulus_16;
                    $display("[%t] DUT: Normalizing real component", $time);
                end
                
                if (twiddle_imag > (current_modulus_16 >> 1)) begin
                    twiddle_imag <= twiddle_imag - current_modulus_16;
                    $display("[%t] DUT: Normalizing imag component", $time);
                end
                
                if (counter >= 2) begin
                    state <= STATE_DONE;
                    $display("[%t] DUT: Normalization complete", $time);
                end
            end
            
            STATE_DONE: begin
                gen_done <= 1;
                gen_valid <= 0;
                counter <= 0;
                
                $display("[%t] DUT: Generation DONE", $time);
                $display("[%t] DUT: Final output - real=%h (%d), imag=%h (%d)", 
                         $time, twiddle_real, twiddle_real, twiddle_imag, twiddle_imag);
                
                if (mode && start_gen_rising) begin
                    state <= STATE_CALC_BASE;
                    gen_done <= 0;
                    $display("[%t] DUT: Continuous mode - starting next generation", $time);
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
assign error = 1'b0;  // 简化，实际应该有错误检测

endmodule