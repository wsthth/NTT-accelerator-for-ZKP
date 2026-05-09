// ntt_twiddle_dynamic_gen_with_memory.v
`timescale 1ns / 1ps

module ntt_twiddle_dynamic_gen_with_memory #(
    // ================= 可配置参数 =================
    parameter DATA_WIDTH        = 256,        // 数据位宽（大模数256位）
    parameter MAX_MODULUS_BITS  = 384,        // 最大模数位宽
    parameter PARALLEL_LEVEL    = 4,          // 并行度
    parameter PIPELINE_DEPTH    = 3,          // 流水线深度
    parameter SRAM_DEPTH        = 128,        // SRAM深度（高频访问缓存）
    parameter BRAM_DEPTH        = 1024,       // BRAM深度（低频访问缓存）
    parameter CACHE_THRESHOLD   = 3           // 访问频率阈值
)(
    // ================= 时钟与复位 =================
    input  wire                          clk,
    input  wire                          reset_n,
    
    // ================= 控制接口 =================
    input  wire                          start_gen,
    input  wire                          mode,           // 0:正向NTT，1:逆向NTT
    
    // ================= 配置参数 =================
    input  wire [DATA_WIDTH-1:0]         modulus,        // 模数（大模数256位）
    input  wire [DATA_WIDTH-1:0]         Np,             // -N^{-1} mod R (蒙哥马利参数)
    input  wire [DATA_WIDTH-1:0]         R2_mod_N,       // R^2 mod N (蒙哥马利参数)
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
    output reg                           parallel_active,
    output reg  [7:0]                    cache_hit_rate, // 缓存命中率
    
    // ================= 存储状态 =================
    output reg  [7:0]                    sram_usage,     // SRAM使用率
    output reg  [7:0]                    bram_usage,     // BRAM使用率
    output reg                           eviction_active, // 淘汰机制激活
    
    // ================= 错误指示 =================
    output reg                           error
);

// ================= 参数定义 =================
localparam ADDR_WIDTH = 16; // 地址位宽，支持最大2^16个旋转因子

// ================= 状态定义 =================
localparam STATE_IDLE          = 4'b0000;
localparam STATE_CACHE_CHECK   = 4'b0001;
localparam STATE_CALC_EXPONENT = 4'b0010;
localparam STATE_CALC_BASE     = 4'b0011;
localparam STATE_PARALLEL_INIT = 4'b0100;
localparam STATE_PARALLEL_GEN  = 4'b0101;
localparam STATE_SELECT_OUTPUT = 4'b0110;
localparam STATE_UPDATE_CACHE  = 4'b0111;
localparam STATE_DONE          = 4'b1000;

localparam MEM_STATE_IDLE       = 3'b000;
localparam MEM_STATE_LOOKUP     = 3'b001;
localparam MEM_STATE_UPDATE     = 3'b010;
localparam MEM_STATE_EVICT      = 3'b011;
localparam MEM_STATE_WRITE_BACK = 3'b100;

// ================= 内部寄存器 =================
reg [3:0]                   state;
reg [31:0]                  counter;
reg [DATA_WIDTH-1:0]        current_modulus;
reg [DATA_WIDTH-1:0]        current_Np;
reg [DATA_WIDTH-1:0]        current_R2_mod_N;
reg [DATA_WIDTH-1:0]        current_primitive_root;
reg [DATA_WIDTH-1:0]        current_base_twiddle;
reg [15:0]                  current_N;
reg [7:0]                   current_stage;
reg [7:0]                   current_index;

// 幂次计算相关
reg [31:0]                  target_exponent;
reg [DATA_WIDTH-1:0]        step_value;      // 步进值：ω_base^{N/2^{s+1}}
reg [DATA_WIDTH-1:0]        base_value;      // 基础值：ω_base^{rev_index}

// 并行生成相关
wire [DATA_WIDTH*PARALLEL_LEVEL-1:0] parallel_twiddles_packed;
reg [DATA_WIDTH-1:0]        parallel_twiddles_array [0:PARALLEL_LEVEL-1];
reg                         parallel_start;
wire                        parallel_done;

// 存储管理相关
reg [31:0]                  sram_access_counter [0:SRAM_DEPTH-1];  // SRAM访问计数器
reg [15:0]                  sram_access_time [0:SRAM_DEPTH-1];     // SRAM访问时间戳
reg [ADDR_WIDTH-1:0]        sram_tag_array [0:SRAM_DEPTH-1];       // SRAM标签（地址）
reg                         sram_valid [0:SRAM_DEPTH-1];           // SRAM有效位
reg [DATA_WIDTH-1:0]        sram_data_array [0:SRAM_DEPTH-1];      // SRAM数据

reg [31:0]                  bram_access_counter [0:BRAM_DEPTH-1];  // BRAM访问计数器
reg [ADDR_WIDTH-1:0]        bram_tag_array [0:BRAM_DEPTH-1];       // BRAM标签
reg                         bram_valid [0:BRAM_DEPTH-1];           // BRAM有效位
reg [DATA_WIDTH-1:0]        bram_data_array [0:BRAM_DEPTH-1];      // BRAM数据

// 缓存查找相关
reg [ADDR_WIDTH-1:0]        current_twiddle_addr;
reg [DATA_WIDTH-1:0]        cache_rd_data;
reg                         cache_hit;
reg                         sram_hit;
reg                         bram_hit;
reg                         cache_miss;
reg [7:0]                   cache_hit_type; // 0=未命中，1=SRAM命中，2=BRAM命中

// 存储管理状态机
reg [2:0]                   mem_state;
reg [31:0]                  mem_counter;
reg [7:0]                   lru_sram_index;
reg [ADDR_WIDTH-1:0]        evict_addr;

// 性能统计
reg [31:0]                  total_accesses;
reg [31:0]                  cache_hits;

// 控制信号同步
reg                         start_gen_sync1, start_gen_sync2;
wire                        start_gen_rising;

// 模运算接口
wire [DATA_WIDTH-1:0]       mod_mult_result;
wire                        mod_mult_done;
reg                         mod_mult_start;
reg [DATA_WIDTH-1:0]        mod_mult_a;
reg [DATA_WIDTH-1:0]        mod_mult_b;

wire [DATA_WIDTH-1:0]       mod_pow_result;
wire                        mod_pow_done;
reg                         mod_pow_start;
reg [DATA_WIDTH-1:0]        mod_pow_base;
reg [DATA_WIDTH-1:0]        mod_pow_exponent;

// ================= 解包并行数组 =================
integer j;
always @(*) begin
    for (j = 0; j < PARALLEL_LEVEL; j = j + 1) begin
        parallel_twiddles_array[j] = parallel_twiddles_packed[j*DATA_WIDTH +: DATA_WIDTH];
    end
end

// ================= 同步逻辑 =================
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        start_gen_sync1 <= 0;
        start_gen_sync2 <= 0;
    end else begin
        start_gen_sync1 <= start_gen;
        start_gen_sync2 <= start_gen_sync1;
    end
end

assign start_gen_rising = start_gen_sync1 && !start_gen_sync2;

// ================= 辅助函数定义 =================

// 位反转函数
function [7:0] bit_reverse_8;
    input [7:0] x;
    integer i;
    begin
        bit_reverse_8 = 0;
        for (i = 0; i < 8; i = i + 1) begin
            bit_reverse_8[i] = x[7-i];
        end
    end
endfunction

// 地址生成函数
function [ADDR_WIDTH-1:0] generate_twiddle_addr;
    input [7:0] stage;
    input [7:0] index;
    input mode;
    reg [ADDR_WIDTH-1:0] addr;
    begin
        // 地址编码：最高位=模式，次高位=stage，低位=index
        addr = {mode, stage, index};
        generate_twiddle_addr = addr;
    end
endfunction

// 指数计算函数
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
        
        // NTT旋转因子指数计算公式
        power = rev_index * (N >> (stage + 1));
        
        if (mode == 1) begin
            // 逆向NTT：使用负指数
            power = (current_modulus - 1) - (power % (current_modulus - 1));
        end
        
        calculate_exponent = power;
    end
endfunction

// LRU查找函数
function integer find_lru_sram_entry;
    integer i;
    reg [31:0] min_counter;
    integer min_index;
    begin
        min_counter = sram_access_counter[0];
        min_index = 0;
        
        for (i = 1; i < SRAM_DEPTH; i = i + 1) begin
            if (sram_access_counter[i] < min_counter) begin
                min_counter = sram_access_counter[i];
                min_index = i;
            end else if (sram_access_counter[i] == min_counter && 
                        sram_access_time[i] < sram_access_time[min_index]) begin
                min_index = i;
            end
        end
        
        find_lru_sram_entry = min_index;
    end
endfunction

// ================= 模块实例化 =================

// 大数模乘模块实例
modular_multiplier_256bit mod_mult_inst (
    .clk(clk),
    .rst_n(reset_n),
    .start(mod_mult_start),
    .a(mod_mult_a),
    .b(mod_mult_b),
    .N(current_modulus),
    .Np(current_Np),
    .R2_mod_N(current_R2_mod_N),
    .result(mod_mult_result),
    .done(mod_mult_done),
    .busy()
);

// 模幂模块实例
modular_exponentiation #(
    .DATA_WIDTH(256)
) mod_pow_inst (
    .clk(clk),
    .reset_n(reset_n),
    .start(mod_pow_start),
    .base(mod_pow_base),
    .exponent(mod_pow_exponent),
    .modulus(current_modulus),
    .Np(current_Np),
    .R2_mod_N(current_R2_mod_N),
    .result(mod_pow_result),
    .done(mod_pow_done)
);

// 并行递推单元实例化
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
    .Np(current_Np),
    .R2_mod_N(current_R2_mod_N),
    .twiddles_packed(parallel_twiddles_packed),
    .done(parallel_done)
);

// ================= 存储初始化 =================
integer k;
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        // 初始化SRAM缓存
        for (k = 0; k < SRAM_DEPTH; k = k + 1) begin
            sram_valid[k] <= 0;
            sram_access_counter[k] <= 0;
            sram_access_time[k] <= 0;
            sram_tag_array[k] <= 0;
            sram_data_array[k] <= 0;
        end
        
        // 初始化BRAM缓存
        for (k = 0; k < BRAM_DEPTH; k = k + 1) begin
            bram_valid[k] <= 0;
            bram_access_counter[k] <= 0;
            bram_tag_array[k] <= 0;
            bram_data_array[k] <= 0;
        end
        
        // 初始化性能统计
        total_accesses <= 0;
        cache_hits <= 0;
        cache_hit_rate <= 0;
        sram_usage <= 0;
        bram_usage <= 0;
        eviction_active <= 0;
        
    end else begin
        // 更新总访问次数
        if (start_gen_rising) begin
            total_accesses <= total_accesses + 1;
        end
        
        // 更新命中率
        if (gen_done && total_accesses > 0) begin
            cache_hit_rate <= (cache_hits * 100) / total_accesses;
        end
    end
end

// ================= 缓存查找逻辑 =================
integer m;
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        sram_hit <= 0;
        bram_hit <= 0;
        cache_hit <= 0;
        cache_miss <= 0;
        cache_hit_type <= 0;
        cache_rd_data <= 0;
        current_twiddle_addr <= 0;
    end else begin
        // 计算当前旋转因子地址
        current_twiddle_addr <= generate_twiddle_addr(current_stage, current_index, mode);
        
        // 默认值
        sram_hit <= 0;
        bram_hit <= 0;
        cache_hit <= 0;
        cache_miss <= 0;
        
        // 第一步：查找SRAM（高频缓存）
        for (m = 0; m < SRAM_DEPTH; m = m + 1) begin
            if (sram_valid[m] && sram_tag_array[m] == current_twiddle_addr) begin
                sram_hit <= 1;
                bram_hit <= 0;
                cache_hit <= 1;
                cache_hit_type <= 1;
                cache_rd_data <= sram_data_array[m];
                
                // 更新访问计数和时间戳
                sram_access_counter[m] <= sram_access_counter[m] + 1;
                sram_access_time[m] <= gen_cycles[15:0];
                
                // 更新命中统计
                cache_hits <= cache_hits + 1;
                
                $display("[%t] CACHE: SRAM HIT at addr=%h, index=%d", 
                         $time, current_twiddle_addr, m);
                break;
            end
        end
        
        // 第二步：查找BRAM（低频缓存）
        if (!cache_hit) begin
            for (m = 0; m < BRAM_DEPTH; m = m + 1) begin
                if (bram_valid[m] && bram_tag_array[m] == current_twiddle_addr) begin
                    sram_hit <= 0;
                    bram_hit <= 1;
                    cache_hit <= 1;
                    cache_hit_type <= 2;
                    cache_rd_data <= bram_data_array[m];
                    
                    // 更新BRAM访问计数
                    bram_access_counter[m] <= bram_access_counter[m] + 1;
                    
                    // 更新命中统计
                    cache_hits <= cache_hits + 1;
                    
                    $display("[%t] CACHE: BRAM HIT at addr=%h, index=%d", 
                             $time, current_twiddle_addr, m);
                    break;
                end
            end
        end
        
        // 缓存未命中
        if (!cache_hit && start_gen_rising) begin
            cache_miss <= 1;
            cache_hit_type <= 0;
            $display("[%t] CACHE: MISS at addr=%h", $time, current_twiddle_addr);
        end
    end
end

// ================= 存储管理状态机 =================
integer n;
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        mem_state <= MEM_STATE_IDLE;
        mem_counter <= 0;
        lru_sram_index <= 0;
        evict_addr <= 0;
        
    end else begin
        case (mem_state)
            MEM_STATE_IDLE: begin
                if (cache_miss && gen_done) begin
                    // 缓存未命中，准备写入新数据
                    mem_state <= MEM_STATE_LOOKUP;
                    mem_counter <= 0;
                    $display("[%t] MEM: Cache miss, starting lookup", $time);
                end
            end
            
            MEM_STATE_LOOKUP: begin
                mem_counter <= mem_counter + 1;
                
                if (mem_counter == 0) begin
                    // 根据访问频率决定存储位置
                    if (current_stage <= 3) begin // 前4阶段：高频，存SRAM
                        lru_sram_index <= find_lru_sram_entry();
                        
                        if (sram_valid[lru_sram_index]) begin
                            // SRAM已满，需要淘汰
                            mem_state <= MEM_STATE_EVICT;
                            evict_addr <= sram_tag_array[lru_sram_index];
                            $display("[%t] MEM: SRAM full, need eviction at index=%d", 
                                     $time, lru_sram_index);
                        end else begin
                            // 直接写入SRAM
                            sram_tag_array[lru_sram_index] <= current_twiddle_addr;
                            sram_data_array[lru_sram_index] <= twiddle_out;
                            sram_valid[lru_sram_index] <= 1;
                            sram_access_counter[lru_sram_index] <= 1;
                            sram_access_time[lru_sram_index] <= gen_cycles[15:0];
                            
                            mem_state <= MEM_STATE_IDLE;
                            $display("[%t] MEM: Direct write to SRAM index=%d", 
                                     $time, lru_sram_index);
                        end
                    end else begin
                        // 中低频，存BRAM
                        integer bram_idx = current_twiddle_addr % BRAM_DEPTH;
                        bram_tag_array[bram_idx] <= current_twiddle_addr;
                        bram_data_array[bram_idx] <= twiddle_out;
                        bram_valid[bram_idx] <= 1;
                        bram_access_counter[bram_idx] <= 1;
                        
                        mem_state <= MEM_STATE_IDLE;
                        $display("[%t] MEM: Write to BRAM index=%d", $time, bram_idx);
                    end
                end
            end
            
            MEM_STATE_EVICT: begin
                mem_counter <= mem_counter + 1;
                eviction_active <= 1;
                
                if (mem_counter == 0) begin
                    // 执行淘汰：将SRAM中的数据降级到BRAM
                    integer bram_idx = evict_addr % BRAM_DEPTH;
                    
                    // 更新BRAM
                    bram_tag_array[bram_idx] <= evict_addr;
                    bram_data_array[bram_idx] <= sram_data_array[lru_sram_index];
                    bram_valid[bram_idx] <= 1;
                    bram_access_counter[bram_idx] <= 
                        sram_access_counter[lru_sram_index] >> 1; // 访问计数减半
                    
                    $display("[%t] MEM: Evicting SRAM index=%d to BRAM index=%d", 
                             $time, lru_sram_index, bram_idx);
                end
                
                if (mem_counter == 1) begin
                    mem_state <= MEM_STATE_WRITE_BACK;
                end
            end
            
            MEM_STATE_WRITE_BACK: begin
                mem_counter <= mem_counter + 1;
                
                if (mem_counter == 0) begin
                    // 写入新的高频数据到SRAM
                    sram_tag_array[lru_sram_index] <= current_twiddle_addr;
                    sram_data_array[lru_sram_index] <= twiddle_out;
                    sram_valid[lru_sram_index] <= 1;
                    sram_access_counter[lru_sram_index] <= 1;
                    sram_access_time[lru_sram_index] <= gen_cycles[15:0];
                    
                    eviction_active <= 0;
                    $display("[%t] MEM: Write back to SRAM index=%d", $time, lru_sram_index);
                end
                
                if (mem_counter == 1) begin
                    mem_state <= MEM_STATE_IDLE;
                end
            end
            
            default: begin
                mem_state <= MEM_STATE_IDLE;
            end
        endcase
    end
end

// ================= 存储状态监控 =================
integer p, q;
always @(posedge clk) begin
    // 统计SRAM使用率
    reg [7:0] sram_count;
    sram_count = 0;
    for (p = 0; p < SRAM_DEPTH; p = p + 1) begin
        if (sram_valid[p]) sram_count = sram_count + 1;
    end
    sram_usage <= (sram_count * 100) / SRAM_DEPTH;
    
    // 统计BRAM使用率
    reg [15:0] bram_count;
    bram_count = 0;
    for (q = 0; q < BRAM_DEPTH; q = q + 1) begin
        if (bram_valid[q]) bram_count = bram_count + 1;
    end
    bram_usage <= (bram_count * 100) / BRAM_DEPTH;
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
        current_Np <= 0;
        current_R2_mod_N <= 0;
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
        
        parallel_active <= 0;
        error <= 0;
        
    end else begin
        gen_cycles <= gen_cycles + 1;
        
        // 默认清零单周期信号
        mod_mult_start <= 0;
        mod_pow_start <= 0;
        parallel_start <= 0;
        gen_valid <= 0;
        parallel_active <= 0;
        
        case (state)
            STATE_IDLE: begin
                gen_done <= 0;
                if (start_gen_rising) begin
                    // 锁存输入参数
                    current_modulus <= modulus;
                    current_Np <= Np;
                    current_R2_mod_N <= R2_mod_N;
                    current_primitive_root <= primitive_root;
                    current_base_twiddle <= base_twiddle;
                    current_N <= N;
                    current_stage <= stage;
                    current_index <= index;
                    
                    counter <= 0;
                    gen_latency <= 0;
                    gen_valid <= 0;
                    gen_done <= 0;
                    
                    state <= STATE_CACHE_CHECK;
                    
                    $display("[%t] NTT: Start generation", $time);
                end
            end
            
            STATE_CACHE_CHECK: begin
                counter <= counter + 1;
                
                if (counter == 1) begin // 给缓存查找一个周期
                    if (cache_hit) begin
                        // 缓存命中，直接输出
                        twiddle_out <= cache_rd_data;
                        gen_valid <= 1;
                        gen_done <= 1;
                        state <= STATE_DONE;
                        
                        $display("[%t] NTT: Cache HIT for stage=%d, index=%d", 
                                 $time, stage, index);
                    end else begin
                        // 缓存未命中，开始动态生成
                        state <= STATE_CALC_EXPONENT;
                        counter <= 0;
                        $display("[%t] NTT: Cache MISS, start dynamic generation", $time);
                    end
                end
            end
            
            STATE_CALC_EXPONENT: begin
                counter <= counter + 1;
                
                if (counter == 0) begin
                    // 计算目标指数
                    target_exponent <= calculate_exponent(current_N, current_stage, current_index, mode);
                    
                    // 计算步进值：ω_base^{N/2^{s+1}}
                    mod_pow_base <= current_base_twiddle;
                    mod_pow_exponent <= {current_N >> (current_stage + 1)};
                    mod_pow_start <= 1;
                end
                
                if (mod_pow_done) begin
                    step_value <= mod_pow_result;
                    state <= STATE_CALC_BASE;
                    counter <= 0;
                end else if (counter > 1000) begin
                    // 超时保护
                    $display("[%t] NTT WARNING: mod_pow timeout", $time);
                    step_value <= current_base_twiddle;
                    state <= STATE_CALC_BASE;
                    counter <= 0;
                end
            end
            
            STATE_CALC_BASE: begin
                counter <= counter + 1;
                
                if (counter == 0) begin
                    // 计算基础值：ω_base^{rev(index)}
                    mod_pow_base <= current_base_twiddle;
                    mod_pow_exponent <= {target_exponent};
                    mod_pow_start <= 1;
                end
                
                if (mod_pow_done) begin
                    base_value <= mod_pow_result;
                    state <= STATE_PARALLEL_INIT;
                    counter <= 0;
                end else if (counter > 1000) begin
                    // 超时保护
                    $display("[%t] NTT WARNING: base calculation timeout", $time);
                    base_value <= current_base_twiddle;
                    state <= STATE_PARALLEL_INIT;
                    counter <= 0;
                end
            end
            
            STATE_PARALLEL_INIT: begin
                counter <= counter + 1;
                
                if (counter == 0) begin
                    // 启动并行单元
                    parallel_start <= 1;
                end
                
                if (counter == 1) begin
                    parallel_start <= 0;
                    state <= STATE_PARALLEL_GEN;
                end
            end
            
            STATE_PARALLEL_GEN: begin
                parallel_active <= 1;
                counter <= counter + 1;
                
                if (parallel_done) begin
                    // 并行生成完成
                    state <= STATE_SELECT_OUTPUT;
                    counter <= 0;
                end else if (counter > 500) begin
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
                        twiddle_out <= parallel_twiddles_array[0];
                    end
                    
                    gen_valid <= 1;
                end
                
                if (counter >= 1) begin
                    state <= STATE_UPDATE_CACHE;
                end
            end
            
            STATE_UPDATE_CACHE: begin
                counter <= counter + 1;
                
                if (counter == 0) begin
                    // 更新缓存
                    if (cache_miss) begin
                        mem_state <= MEM_STATE_LOOKUP;
                        mem_counter <= 0;
                    end
                end
                
                if (counter >= 2) begin
                    state <= STATE_DONE;
                end
            end
            
            STATE_DONE: begin
                gen_done <= 1;
                gen_valid <= 0;
                counter <= 0;
                
                $display("[%t] NTT: Generation DONE", $time);
                
                if (mode && start_gen_rising) begin
                    // 连续模式：准备下一次生成
                    state <= STATE_CACHE_CHECK;
                    gen_done <= 0;
                    counter <= 0;
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
        
        // 错误检测
        if (counter > 2000 && state != STATE_IDLE) begin
            $display("[%t] NTT ERROR: State machine timeout in state=%h", $time, state);
            error <= 1;
            state <= STATE_IDLE;
        end
    end
end

endmodule