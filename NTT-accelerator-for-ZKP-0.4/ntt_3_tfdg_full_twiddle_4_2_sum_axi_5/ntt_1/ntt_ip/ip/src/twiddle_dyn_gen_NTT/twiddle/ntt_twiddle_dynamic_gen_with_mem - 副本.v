// ntt_twiddle_dynamic_gen_with_mem.v
`timescale 1ns / 1ps

module ntt_twiddle_dynamic_gen_with_mem #(
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
    input  wire [DATA_WIDTH-1:0]         modulus,        // 模数
    input  wire [DATA_WIDTH-1:0]         Np,             // -N^{-1} mod R
    input  wire [DATA_WIDTH-1:0]         R2_mod_N,       // R^2 mod N
    input  wire [DATA_WIDTH-1:0]         primitive_root, // 原根g
    input  wire [DATA_WIDTH-1:0]         base_twiddle,   // 基础旋转因子
    input  wire [15:0]                   N,              // NTT长度
    input  wire [7:0]                    stage,          // NTT阶段
    input  wire [7:0]                    index,          // 旋转因子索引
    
    // ================= 生成结果 =================
    output reg  [DATA_WIDTH-1:0]         twiddle_out,    // NTT旋转因子
    output reg                           gen_done,
    output reg                           gen_valid,
    
    // ================= 存储接口 =================
    output wire                          sram_wr_en,
    output wire [10:0]                   sram_addr,
    output wire [DATA_WIDTH-1:0]         sram_wr_data,
    input  wire [DATA_WIDTH-1:0]         sram_rd_data,
    
    output wire                          bram_wr_en,
    output wire [12:0]                   bram_addr,
    output wire [DATA_WIDTH-1:0]         bram_wr_data,
    input  wire [DATA_WIDTH-1:0]         bram_rd_data,
    
    // ================= 性能监控 =================
    output reg  [15:0]                   gen_cycles,
    output reg  [7:0]                    gen_latency,
    output wire                          parallel_active,
    output reg  [7:0]                    cache_hit_rate, // 缓存命中率
    
    // ================= 存储状态 =================
    output wire [7:0]                    sram_usage,     // SRAM使用率
    output wire [7:0]                    bram_usage,     // BRAM使用率
    output wire                          eviction_active, // 淘汰机制激活
    
    // ================= 错误指示 =================
    output wire                          error
);

// ================= 新增存储相关参数 =================
localparam ADDR_WIDTH = 16; // 地址位宽，支持最大2^16个旋转因子

// ================= 新增存储相关寄存器 =================
reg [31:0] access_counter [0:SRAM_DEPTH-1];  // 访问计数器（用于LRU淘汰）
reg [15:0] access_time [0:SRAM_DEPTH-1];     // 访问时间戳
reg [DATA_WIDTH-1:0] sram_cache [0:SRAM_DEPTH-1]; // SRAM缓存
reg                  sram_valid [0:SRAM_DEPTH-1]; // SRAM有效位

reg [31:0] bram_access_counter [0:BRAM_DEPTH-1]; // BRAM访问计数器
reg [DATA_WIDTH-1:0] bram_cache [0:BRAM_DEPTH-1]; // BRAM缓存
reg                  bram_valid [0:BRAM_DEPTH-1]; // BRAM有效位

// 缓存查找相关
wire [ADDR_WIDTH-1:0] twiddle_addr;
reg  [DATA_WIDTH-1:0] cache_rd_data;
reg                   cache_hit;
reg                   sram_hit;
reg                   bram_hit;
reg                   cache_miss;

// ================= 存储管理状态机 =================
localparam MEM_STATE_IDLE       = 3'b000;
localparam MEM_STATE_LOOKUP     = 3'b001;
localparam MEM_STATE_UPDATE     = 3'b010;
localparam MEM_STATE_EVICT      = 3'b011;
localparam MEM_STATE_WRITE_BACK = 3'b100;

reg [2:0] mem_state;

// ================= 地址生成函数 =================
// 根据stage和index生成唯一地址
function [ADDR_WIDTH-1:0] generate_twiddle_addr;
    input [7:0] stage;
    input [7:0] index;
    input mode;
    reg [ADDR_WIDTH-1:0] addr;
begin
    // 地址编码：最高位=模式，次高位=stage，低位=index
    addr = {mode, stage, index[6:0]};
    generate_twiddle_addr = addr;
end
endfunction

// ================= 缓存查找逻辑 =================
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        sram_hit <= 0;
        bram_hit <= 0;
        cache_hit <= 0;
        cache_rd_data <= 0;
    end else begin
        // 计算当前旋转因子地址
        twiddle_addr = generate_twiddle_addr(stage, index, mode);
        
        // 第一步：查找SRAM（高频缓存）
        if (sram_valid[twiddle_addr % SRAM_DEPTH] && 
            sram_cache[twiddle_addr % SRAM_DEPTH][ADDR_WIDTH-1:0] == twiddle_addr) begin
            sram_hit <= 1;
            bram_hit <= 0;
            cache_hit <= 1;
            cache_rd_data <= sram_cache[twiddle_addr % SRAM_DEPTH][DATA_WIDTH-1:ADDR_WIDTH];
            
            // 更新访问计数和时间戳
            access_counter[twiddle_addr % SRAM_DEPTH] <= 
                access_counter[twiddle_addr % SRAM_DEPTH] + 1;
            access_time[twiddle_addr % SRAM_DEPTH] <= gen_cycles[15:0];
        end 
        // 第二步：查找BRAM（低频缓存）
        else if (bram_valid[twiddle_addr % BRAM_DEPTH] && 
                 bram_cache[twiddle_addr % BRAM_DEPTH][ADDR_WIDTH-1:0] == twiddle_addr) begin
            sram_hit <= 0;
            bram_hit <= 1;
            cache_hit <= 1;
            cache_rd_data <= bram_cache[twiddle_addr % BRAM_DEPTH][DATA_WIDTH-1:ADDR_WIDTH];
            
            // 更新BRAM访问计数
            bram_access_counter[twiddle_addr % BRAM_DEPTH] <= 
                bram_access_counter[twiddle_addr % BRAM_DEPTH] + 1;
            
            // 如果BRAM访问次数超过阈值，升级到SRAM
            if (bram_access_counter[twiddle_addr % BRAM_DEPTH] > CACHE_THRESHOLD) begin
                // 触发升级操作
                mem_state <= MEM_STATE_UPDATE;
            end
        end else begin
            sram_hit <= 0;
            bram_hit <= 0;
            cache_hit <= 0;
            cache_miss <= 1;
        end
    end
end

// ================= LRU淘汰算法 =================
function integer find_lru_sram_entry;
    integer i;
    reg [31:0] min_counter;
    integer min_index;
begin
    min_counter = access_counter[0];
    min_index = 0;
    
    for (i = 1; i < SRAM_DEPTH; i = i + 1) begin
        if (access_counter[i] < min_counter) begin
            min_counter = access_counter[i];
            min_index = i;
        end else if (access_counter[i] == min_counter && 
                    access_time[i] < access_time[min_index]) begin
            // 相同访问次数时，选择更早访问的
            min_index = i;
        end
    end
    
    find_lru_sram_entry = min_index;
end
endfunction

// ================= 存储管理状态机 =================
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        mem_state <= MEM_STATE_IDLE;
        // 初始化缓存
        for (integer i = 0; i < SRAM_DEPTH; i = i + 1) begin
            sram_valid[i] <= 0;
            access_counter[i] <= 0;
            access_time[i] <= 0;
        end
        for (integer j = 0; j < BRAM_DEPTH; j = j + 1) begin
            bram_valid[j] <= 0;
            bram_access_counter[j] <= 0;
        end
    end else begin
        case (mem_state)
            MEM_STATE_IDLE: begin
                if (cache_miss && gen_done) begin
                    // 缓存未命中，准备写入新数据
                    mem_state <= MEM_STATE_LOOKUP;
                end
            end
            
            MEM_STATE_LOOKUP: begin
                // 根据访问频率决定存储位置
                if (stage <= 3) begin // 前4阶段：高频，存SRAM
                    integer lru_idx = find_lru_sram_entry();
                    
                    if (sram_valid[lru_idx]) begin
                        // SRAM已满，需要淘汰
                        mem_state <= MEM_STATE_EVICT;
                    end else begin
                        // 直接写入SRAM
                        sram_cache[lru_idx] <= {twiddle_out, twiddle_addr};
                        sram_valid[lru_idx] <= 1;
                        access_counter[lru_idx] <= 1;
                        access_time[lru_idx] <= gen_cycles[15:0];
                        mem_state <= MEM_STATE_IDLE;
                    end
                end else begin
                    // 中低频，存BRAM
                    bram_cache[twiddle_addr % BRAM_DEPTH] <= {twiddle_out, twiddle_addr};
                    bram_valid[twiddle_addr % BRAM_DEPTH] <= 1;
                    bram_access_counter[twiddle_addr % BRAM_DEPTH] <= 1;
                    mem_state <= MEM_STATE_IDLE;
                end
            end
            
            MEM_STATE_EVICT: begin
                // 执行淘汰：将SRAM中的数据降级到BRAM
                integer lru_idx = find_lru_sram_entry();
                reg [ADDR_WIDTH-1:0] evict_addr = sram_cache[lru_idx][ADDR_WIDTH-1:0];
                
                // 将淘汰的数据写入BRAM
                bram_cache[evict_addr % BRAM_DEPTH] <= sram_cache[lru_idx];
                bram_valid[evict_addr % BRAM_DEPTH] <= 1;
                bram_access_counter[evict_addr % BRAM_DEPTH] <= 
                    access_counter[lru_idx] >> 1; // 访问计数减半
                
                // 清空SRAM条目
                sram_valid[lru_idx] <= 0;
                access_counter[lru_idx] <= 0;
                
                mem_state <= MEM_STATE_WRITE_BACK;
            end
            
            MEM_STATE_WRITE_BACK: begin
                // 写入新的高频数据到SRAM
                integer lru_idx = find_lru_sram_entry();
                sram_cache[lru_idx] <= {twiddle_out, twiddle_addr};
                sram_valid[lru_idx] <= 1;
                access_counter[lru_idx] <= 1;
                access_time[lru_idx] <= gen_cycles[15:0];
                
                mem_state <= MEM_STATE_IDLE;
            end
            
            MEM_STATE_UPDATE: begin
                // 将BRAM中的数据升级到SRAM
                if (bram_hit) begin
                    integer lru_idx = find_lru_sram_entry();
                    
                    // 先淘汰一个SRAM条目到BRAM
                    reg [ADDR_WIDTH-1:0] evict_addr = sram_cache[lru_idx][ADDR_WIDTH-1:0];
                    bram_cache[evict_addr % BRAM_DEPTH] <= sram_cache[lru_idx];
                    bram_valid[evict_addr % BRAM_DEPTH] <= 1;
                    
                    // 将BRAM中的数据升级到SRAM
                    sram_cache[lru_idx] <= bram_cache[twiddle_addr % BRAM_DEPTH];
                    sram_valid[lru_idx] <= 1;
                    access_counter[lru_idx] <= bram_access_counter[twiddle_addr % BRAM_DEPTH];
                    access_time[lru_idx] <= gen_cycles[15:0];
                    
                    // 清空BRAM条目
                    bram_valid[twiddle_addr % BRAM_DEPTH] <= 0;
                end
                mem_state <= MEM_STATE_IDLE;
            end
        endcase
    end
end

// ================= 修改主状态机 =================
// 在原有STATE_IDLE后添加缓存检查状态
localparam STATE_CACHE_CHECK    = 4'b0111;

// 修改主状态机流程
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        // ... 原有复位逻辑 ...
    end else begin
        case (state)
            STATE_IDLE: begin
                if (start_gen_rising) begin
                    // 锁存参数
                    // ... 原有锁存逻辑 ...
                    
                    // 首先检查缓存
                    state <= STATE_CACHE_CHECK;
                    counter <= 0;
                end
            end
            
            STATE_CACHE_CHECK: begin
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
                    $display("[%t] NTT: Cache MISS, start dynamic generation", $time);
                end
            end
            
            // ... 原有其他状态 ...
            
            STATE_DONE: begin
                // 在生成完成后，更新缓存命中率统计
                if (cache_hit) begin
                    cache_hit_rate <= (cache_hit_rate * 7 + 8'd100) / 8; // 滑动平均
                end else begin
                    cache_hit_rate <= (cache_hit_rate * 7 + 8'd0) / 8;
                end
                
                // ... 原有结束逻辑 ...
            end
        endcase
    end
end

// ================= 存储状态监控 =================
reg [7:0] sram_count;
reg [7:0] bram_count;

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        sram_count <= 0;
        bram_count <= 0;
    end else begin
        // 统计SRAM使用率
        sram_count = 0;
        for (integer i = 0; i < SRAM_DEPTH; i = i + 1) begin
            if (sram_valid[i]) sram_count = sram_count + 1;
        end
        sram_usage = (sram_count * 100) / SRAM_DEPTH;
        
        // 统计BRAM使用率
        bram_count = 0;
        for (integer j = 0; j < BRAM_DEPTH; j = j + 1) begin
            if (bram_valid[j]) bram_count = bram_count + 1;
        end
        bram_usage = (bram_count * 100) / BRAM_DEPTH;
    end
end

// ================= 外部存储接口 =================
assign sram_wr_en = (mem_state == MEM_STATE_WRITE_BACK);
assign sram_addr = twiddle_addr[10:0]; // 11位地址对应128深度
assign sram_wr_data = twiddle_out;

assign bram_wr_en = (mem_state == MEM_STATE_EVICT || mem_state == MEM_STATE_UPDATE);
assign bram_addr = twiddle_addr[12:0]; // 13位地址对应1024深度
assign bram_wr_data = twiddle_out;

assign eviction_active = (mem_state == MEM_STATE_EVICT);

// ================= 原有模块内容保持不变 =================
// ... 原有并行生成、模幂计算等逻辑 ...

endmodule