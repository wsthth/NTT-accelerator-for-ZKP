// twiddle_bram.v：模拟硬件BRAM（LRU替换+超时管理）
module twiddle_bram #(
    parameter MAX_CAP = 8,          // BRAM容量（与Python的MAX_STORAGE_CAP=8一致）
    parameter TIMEOUT_THRESH = 32,  // 超时阈值（与Python的32clk一致）
    parameter K_WIDTH = 8,          // k值位宽
    parameter TW_WIDTH = 384        // 旋转因子位宽（384bit）
)(
    input  wire clk,
    input  wire rst_n,
    // 写端口（存储新因子）
    input  wire [K_WIDTH-1:0]  wr_k,
    input  wire [TW_WIDTH-1:0] wr_twiddle,
    input  wire                wr_en,
    // 读/复用校验端口
    input  wire [K_WIDTH-1:0]  rd_k,
    input  wire                rd_en,
    output reg                 reuse_flag,  // 复用成功标志
    output reg [TW_WIDTH-1:0]  rd_twiddle,  // 读出的因子
    // 状态输出
    output reg [3:0]           storage_cnt  // 当前存储的因子数
);

// BRAM存储阵列：{twiddle, valid, timer, last_use}
reg [TW_WIDTH+1+5+15:0] bram [0:MAX_CAP-1];  // valid(1bit)+timer(5bit)+last_use(15bit)
reg [K_WIDTH-1:0] lru_queue [0:MAX_CAP-1];   // LRU队列（与Python一致）
reg [3:0] lru_ptr;                           // LRU队列指针

// 初始化
integer i;
always @(posedge rst_n) begin
    if(!rst_n) begin
        storage_cnt <= 0;
        lru_ptr <= 0;
        for(i=0; i<MAX_CAP; i=i+1) begin
            bram[i] <= 0;
            lru_queue[i] <= 0;
        end
    end
end

// 1. 写逻辑（存储新因子，LRU替换）
always @(posedge clk) begin
    if(wr_en) begin
        // 容量超限：替换LRU队列首的k（与Python的LRU替换一致）
        if(storage_cnt >= MAX_CAP) begin
            // 找到LRU队列首的k对应的BRAM地址
            reg [3:0] lru_addr;
            for(i=0; i<MAX_CAP; i=i+1) begin
                if(lru_queue[i] == lru_queue[0]) lru_addr = i;
            end
            bram[lru_addr] <= {wr_twiddle, 1'b1, 5'd0, 15'd0};  // valid=1, timer=0
            lru_queue[0] <= wr_k;  // 更新LRU队列
        end else begin
            // 容量充足，直接存储
            bram[storage_cnt] <= {wr_twiddle, 1'b1, 5'd0, 15'd0};
            lru_queue[storage_cnt] <= wr_k;
            storage_cnt <= storage_cnt + 1;
        end
    end
end

// 2. 计时器更新（每clk+1，超时置无效，与Python一致）
always @(posedge clk) begin
    for(i=0; i<MAX_CAP; i=i+1) begin
        if(bram[i][TW_WIDTH+1] == 1'b1) begin  // valid=1
            reg [4:0] timer;
            timer = bram[i][TW_WIDTH+1-1 : TW_WIDTH+1-5];
            timer = timer + 1;
            if(timer > TIMEOUT_THRESH) begin
                bram[i][TW_WIDTH+1] <= 1'b0;  // 超时置无效
            end else begin
                bram[i][TW_WIDTH+1-1 : TW_WIDTH+1-5] <= timer;
            end
        end
    end
end

// 3. 复用校验逻辑（与Python的check_factor_reuse一致）
always @(posedge clk) begin
    if(rd_en) begin
        reuse_flag <= 1'b0;
        rd_twiddle <= 0;
        // 遍历BRAM查找k
        for(i=0; i<MAX_CAP; i=i+1) begin
            if(lru_queue[i] == rd_k && bram[i][TW_WIDTH+1] == 1'b1) begin
                // 有效且未超时，复用成功
                reuse_flag <= 1'b1;
                rd_twiddle <= bram[i][TW_WIDTH-1:0];
                // 重置计时器（与Python一致）
                bram[i][TW_WIDTH+1-1 : TW_WIDTH+1-5] <= 5'd0;
                // 更新LRU队列（移到队尾）
                reg [K_WIDTH-1:0] tmp_k;
                tmp_k = lru_queue[i];
                for(integer j=i; j<MAX_CAP-1; j=j+1) begin
                    lru_queue[j] = lru_queue[j+1];
                end
                lru_queue[MAX_CAP-1] = tmp_k;
                break;
            end
        end
    end
end

endmodule

