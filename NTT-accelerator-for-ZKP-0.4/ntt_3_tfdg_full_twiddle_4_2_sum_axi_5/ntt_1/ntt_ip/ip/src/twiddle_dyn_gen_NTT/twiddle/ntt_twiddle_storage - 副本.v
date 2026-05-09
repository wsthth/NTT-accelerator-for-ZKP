// ntt_twiddle_storage_fixed.v
`timescale 1ns / 1ps

module ntt_twiddle_storage #(
    parameter DATA_WIDTH  = 32,
    parameter SRAM_DEPTH  = 32,
    parameter BRAM_DEPTH  = 64,
    parameter STAGE_WIDTH = 8,
    parameter FREQ_WIDTH  = 4,
    parameter TIMEOUT     = 16'd50
)(
    input  wire                    clk,
    input  wire                    reset_n,
    input  wire                    store_en,
    input  wire                    lookup_en,
    input  wire [15:0]             addr_in,
    input  wire [DATA_WIDTH-1:0]   data_in,
    output reg  [DATA_WIDTH-1:0]   data_out,
    output reg                     hit,
    output reg                     ready,
    input  wire [STAGE_WIDTH-1:0]  stage
);

// 地址宽度计算
localparam SRAM_ADDR_WIDTH = 5;  // log2(32) = 5
localparam BRAM_ADDR_WIDTH = 6;  // log2(64) = 6

// 状态定义
localparam STATE_IDLE    = 2'b00;
localparam STATE_LOOKUP  = 2'b01;
localparam STATE_STORE   = 2'b10;
localparam STATE_CLEANUP = 2'b11;

// RAM接口信号
reg sram_we;
reg [SRAM_ADDR_WIDTH-1:0] sram_waddr;
reg [SRAM_ADDR_WIDTH-1:0] sram_raddr;
reg [DATA_WIDTH-1:0] sram_din;
wire [DATA_WIDTH-1:0] sram_dout;

reg bram_we;
reg [BRAM_ADDR_WIDTH-1:0] bram_waddr;
reg [BRAM_ADDR_WIDTH-1:0] bram_raddr;
reg [DATA_WIDTH-1:0] bram_din;
wire [DATA_WIDTH-1:0] bram_dout;

// 实例化RAM模块
simple_dual_port_ram #(
    .WIDTH(DATA_WIDTH),
    .DEPTH(SRAM_DEPTH),
    .ADDR_WIDTH(SRAM_ADDR_WIDTH)
) sram_inst (
    .clk(clk),
    .we(sram_we),
    .waddr(sram_waddr),
    .raddr(sram_raddr),
    .din(sram_din),
    .dout(sram_dout)
);

simple_dual_port_ram #(
    .WIDTH(DATA_WIDTH),
    .DEPTH(BRAM_DEPTH),
    .ADDR_WIDTH(BRAM_ADDR_WIDTH)
) bram_inst (
    .clk(clk),
    .we(bram_we),
    .waddr(bram_waddr),
    .raddr(bram_raddr),
    .din(bram_din),
    .dout(bram_dout)
);

// 元数据 - 使用寄存器数组
reg [15:0] sram_tag [0:SRAM_DEPTH-1];
reg sram_valid [0:SRAM_DEPTH-1];
reg [FREQ_WIDTH-1:0] sram_freq [0:SRAM_DEPTH-1];
reg [15:0] sram_last_access [0:SRAM_DEPTH-1];

reg [15:0] bram_tag [0:BRAM_DEPTH-1];
reg bram_valid [0:BRAM_DEPTH-1];
reg [FREQ_WIDTH-1:0] bram_freq [0:BRAM_DEPTH-1];
reg [15:0] bram_last_access [0:BRAM_DEPTH-1];

// 状态机
reg [1:0] state;
reg [2:0] counter;
reg [15:0] global_timer;
reg [5:0] cleanup_index;

// 临时寄存器
reg [15:0] current_addr;
reg [DATA_WIDTH-1:0] current_data;
reg [STAGE_WIDTH-1:0] current_stage;
reg found_in_sram;
reg found_in_bram;

// 循环变量
integer i;

// 简单的哈希函数
function [SRAM_ADDR_WIDTH-1:0] hash_sram;
    input [15:0] addr;
    begin
        // 取低SRAM_ADDR_WIDTH位作为哈希
        hash_sram = addr[SRAM_ADDR_WIDTH-1:0];
    end
endfunction

function [BRAM_ADDR_WIDTH-1:0] hash_bram;
    input [15:0] addr;
    begin
        // 取低BRAM_ADDR_WIDTH位作为哈希
        hash_bram = addr[BRAM_ADDR_WIDTH-1:0];
    end
endfunction

// 主状态机
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        // 初始化
        state <= STATE_IDLE;
        counter <= 3'b0;
        global_timer <= 16'b0;
        cleanup_index <= 6'b0;
        
        ready <= 1'b1;
        hit <= 1'b0;
        data_out <= {DATA_WIDTH{1'b0}};
        
        sram_we <= 1'b0;
        bram_we <= 1'b0;
        sram_waddr <= {SRAM_ADDR_WIDTH{1'b0}};
        sram_raddr <= {SRAM_ADDR_WIDTH{1'b0}};
        sram_din <= {DATA_WIDTH{1'b0}};
        bram_waddr <= {BRAM_ADDR_WIDTH{1'b0}};
        bram_raddr <= {BRAM_ADDR_WIDTH{1'b0}};
        bram_din <= {DATA_WIDTH{1'b0}};
        
        current_addr <= 16'b0;
        current_data <= {DATA_WIDTH{1'b0}};
        current_stage <= {STAGE_WIDTH{1'b0}};
        found_in_sram <= 1'b0;
        found_in_bram <= 1'b0;
        
        // 初始化元数据
        for (i = 0; i < SRAM_DEPTH; i = i + 1) begin
            sram_valid[i] <= 1'b0;
            sram_tag[i] <= 16'b0;
            sram_freq[i] <= {FREQ_WIDTH{1'b0}};
            sram_last_access[i] <= 16'b0;
        end
        
        for (i = 0; i < BRAM_DEPTH; i = i + 1) begin
            bram_valid[i] <= 1'b0;
            bram_tag[i] <= 16'b0;
            bram_freq[i] <= {FREQ_WIDTH{1'b0}};
            bram_last_access[i] <= 16'b0;
        end
        
    end else begin
        // 更新全局计时器
        global_timer <= global_timer + 1;
        
        // 默认值
        sram_we <= 1'b0;
        bram_we <= 1'b0;
        found_in_sram <= 1'b0;
        found_in_bram <= 1'b0;
        
        case (state)
            STATE_IDLE: begin
                ready <= 1'b1;
                hit <= 1'b0;
                counter <= 3'b0;
                
                // 定期清理（每256周期）
                if (global_timer[7:0] == 8'b0) begin
                    state <= STATE_CLEANUP;
                    cleanup_index <= 6'b0;
                    ready <= 1'b0;
                end
                // 处理请求
                else if (lookup_en && ready) begin
                    state <= STATE_LOOKUP;
                    current_addr <= addr_in;
                    ready <= 1'b0;
                    counter <= 3'b0;
                end
                else if (store_en && ready) begin
                    state <= STATE_STORE;
                    current_addr <= addr_in;
                    current_data <= data_in;
                    current_stage <= stage;
                    ready <= 1'b0;
                    counter <= 3'b0;
                end
            end
            
            STATE_LOOKUP: begin
                counter <= counter + 1;
                
                if (counter == 0) begin
                    // 计算哈希地址并读取RAM
                    sram_raddr <= hash_sram(current_addr);
                    bram_raddr <= hash_bram(current_addr);
                end
                else if (counter == 1) begin
                    // 等待RAM输出（同步读有1周期延迟）
                    // 下一周期检查结果
                end
                else if (counter == 2) begin
                    // 检查SRAM命中
                    if (sram_valid[sram_raddr] == 1'b1 && sram_tag[sram_raddr] == current_addr) begin
                        found_in_sram <= 1'b1;
                        hit <= 1'b1;
                        data_out <= sram_dout;
                        
                        // 更新访问统计
                        if (sram_freq[sram_raddr] < {FREQ_WIDTH{1'b1}}) begin
                            sram_freq[sram_raddr] <= sram_freq[sram_raddr] + 1;
                        end
                        sram_last_access[sram_raddr] <= global_timer;
                    end
                    // 检查BRAM命中
                    else if (bram_valid[bram_raddr] == 1'b1 && bram_tag[bram_raddr] == current_addr) begin
                        found_in_bram <= 1'b1;
                        hit <= 1'b1;
                        data_out <= bram_dout;
                        
                        // 更新访问统计
                        if (bram_freq[bram_raddr] < {FREQ_WIDTH{1'b1}}) begin
                            bram_freq[bram_raddr] <= bram_freq[bram_raddr] + 1;
                        end
                        bram_last_access[bram_raddr] <= global_timer;
                    end
                    
                    // 完成查找
                    ready <= 1'b1;
                    state <= STATE_IDLE;
                end
            end
            
            STATE_STORE: begin
                counter <= counter + 1;
                
                if (counter == 0) begin
                    // 存储策略：stage <= 3 存SRAM，否则存BRAM
                    if (current_stage <= 3) begin
                        // 存SRAM
                        sram_we <= 1'b1;
                        sram_waddr <= hash_sram(current_addr);
                        sram_din <= current_data;
                        
                        // 更新SRAM元数据
                        sram_valid[hash_sram(current_addr)] <= 1'b1;
                        sram_tag[hash_sram(current_addr)] <= current_addr;
                        sram_freq[hash_sram(current_addr)] <= {FREQ_WIDTH{1'b1}};
                        sram_last_access[hash_sram(current_addr)] <= global_timer;
                    end else begin
                        // 存BRAM
                        bram_we <= 1'b1;
                        bram_waddr <= hash_bram(current_addr);
                        bram_din <= current_data;
                        
                        // 更新BRAM元数据
                        bram_valid[hash_bram(current_addr)] <= 1'b1;
                        bram_tag[hash_bram(current_addr)] <= current_addr;
                        bram_freq[hash_bram(current_addr)] <= 4'b0001;
                        bram_last_access[hash_bram(current_addr)] <= global_timer;
                    end
                end
                else if (counter == 1) begin
                    // 完成存储操作
                    sram_we <= 1'b0;
                    bram_we <= 1'b0;
                    ready <= 1'b1;
                    state <= STATE_IDLE;
                end
            end
            
            STATE_CLEANUP: begin
                // 清理超时的BRAM条目
                if (bram_valid[cleanup_index] == 1'b1 && 
                    (global_timer - bram_last_access[cleanup_index]) > TIMEOUT) begin
                    bram_valid[cleanup_index] <= 1'b0;
                end
                
                cleanup_index <= cleanup_index + 1;
                if (cleanup_index == BRAM_DEPTH - 1) begin
                    state <= STATE_IDLE;
                    ready <= 1'b1;
                end
            end
            
            default: begin
                state <= STATE_IDLE;
            end
        endcase
    end
end

endmodule