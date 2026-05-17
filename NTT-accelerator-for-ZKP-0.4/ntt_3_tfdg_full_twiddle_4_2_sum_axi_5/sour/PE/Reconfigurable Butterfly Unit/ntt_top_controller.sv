// ============================================================================
// 文件名: ntt_top_controller.sv
// 描述: NTT 顶层控制器（BRAM 版本）
//
// 用 simple_dual_port_ram 替代 unpacked 数组，解决 XSim 仿真 bug。
// 所有 BRAM 访问串行化（每周期 1 读或 1 写），处理 1 周期同步读延迟。
//
// 流程：
//   1. 位反转：从 buf_a 顺序读，写到 buf_b[br_table[i]]
//   2. 多级计算：读一个缓冲 → PE → 写另一个缓冲，级间切换
//   3. 输出：从结果缓冲顺序读到 data_out
// ============================================================================
module ntt_top_controller #(
    parameter MAX_WIDTH = 256,
    parameter MAX_RADIX = 16,
    parameter NUM_CORES = 8,
    parameter MAX_N = 8
)(
    input wire clk,
    input wire rst_n,

    // 控制接口
    input wire start_ntt,
    input wire [1:0] radix_mode,
    input wire [7:0] log2_N,

    // 数据输入（$readmemh 模式下不用）
    input wire [MAX_WIDTH-1:0] data_in [0:MAX_N-1],

    // 旋转因子输入
    input wire [MAX_WIDTH-1:0] twiddle_full [0:MAX_N/2-1],

    // 模运算参数
    input wire [MAX_WIDTH-1:0] modulus,
    input wire [MAX_WIDTH-1:0] N_prime,
    input wire [MAX_WIDTH-1:0] R2_mod_N,

    // 数据输出
    output reg [MAX_WIDTH-1:0] data_out [0:MAX_N-1],
    output reg ntt_done,
    output reg ntt_valid
);

    // ========================================================================
    // 地址宽度
    // ========================================================================
    localparam ADDR_W = (MAX_N <= 2)   ? 1 :
                        (MAX_N <= 4)   ? 2 :
                        (MAX_N <= 8)   ? 3 :
                        (MAX_N <= 16)  ? 4 :
                        (MAX_N <= 32)  ? 5 :
                        (MAX_N <= 64)  ? 6 :
                        (MAX_N <= 128) ? 7 :
                        (MAX_N <= 256) ? 8 :
                        (MAX_N <= 512) ? 9 :
                        (MAX_N <= 1024)? 10 :
                        (MAX_N <= 2048)? 11 : 12;

    // ========================================================================
    // BRAM 实例化
    // ========================================================================
    reg                  we_a, we_b;
    reg  [ADDR_W-1:0]    waddr_a, raddr_a;
    reg  [ADDR_W-1:0]    waddr_b, raddr_b;
    reg  [MAX_WIDTH-1:0] din_a, din_b;
    wire [MAX_WIDTH-1:0] dout_a, dout_b;

    simple_dual_port_ram #(.WIDTH(MAX_WIDTH), .DEPTH(MAX_N), .ADDR_WIDTH(ADDR_W), .NAME("buf_a"))
        buf_a_ram (.clk(clk), .we(we_a), .waddr(waddr_a), .raddr(raddr_a),
                   .din(din_a), .dout(dout_a),
                   .tb_we(1'b0), .tb_waddr({ADDR_W{1'b0}}), .tb_din({MAX_WIDTH{1'b0}}));

    simple_dual_port_ram #(.WIDTH(MAX_WIDTH), .DEPTH(MAX_N), .ADDR_WIDTH(ADDR_W), .NAME("buf_b"))
        buf_b_ram (.clk(clk), .we(we_b), .waddr(waddr_b), .raddr(raddr_b),
                   .din(din_b), .dout(dout_b),
                   .tb_we(1'b0), .tb_waddr({ADDR_W{1'b0}}), .tb_din({MAX_WIDTH{1'b0}}));

    // ========================================================================
    // 控制寄存器
    // ========================================================================
    reg [7:0]  stride;
    reg [7:0]  level_cnt;
    reg [7:0]  N_reg;
    reg [1:0]  radix_reg;
    reg [15:0] cnt;            // 通用计数器
    reg        buf_sel;        // 0: 读 buf_a 写 buf_b, 1: 反之
    reg [7:0]  pass_idx;
    reg [7:0]  pass_total;
    reg [7:0]  block_offset;
    reg [7:0]  block_idx;

    // PE 管线接口
    reg                      pe_start;
    wire                     pe_done;
    wire                     pe_result_valid;
    wire [MAX_WIDTH-1:0]     pe_data_out [0:MAX_RADIX-1];
    reg  [MAX_WIDTH-1:0]     pe_data_in [0:MAX_RADIX-1];
    reg  [MAX_WIDTH-1:0]     pe_twiddle [0:MAX_RADIX/2-1];

    // 位反转查找表（$readmemh 加载）
    reg [15:0] br_table [0:MAX_N-1];

    // ========================================================================
    // PE 管线实例化
    // ========================================================================
    reconfigurable_3d_pe_top #(
        .MAX_WIDTH(MAX_WIDTH),
        .MAX_RADIX(MAX_RADIX),
        .NUM_CORES(NUM_CORES)
    ) u_pe (
        .clk(clk), .rst_n(rst_n),
        .radix_mode(radix_reg),
        .width_384_mode(1'b0),
        .parallelism(3'b100),
        .start(pe_start),
        .done(pe_done),
        .result_valid(pe_result_valid),
        .stride(stride),
        .data_in(pe_data_in),
        .twiddle_factors(pe_twiddle),
        .modulus(modulus),
        .N_prime(N_prime),
        .R2_mod_N(R2_mod_N),
        .data_out(pe_data_out)
    );

    // ========================================================================
    // 位反转函数
    // ========================================================================
    function [7:0] bit_reverse;
        input [7:0] x;
        input [7:0] bits;
        reg [7:0] r;
        integer i;
        begin
            r = 0;
            for (i = 0; i < 8; i = i + 1) begin
                if (i < bits) r = (r << 1) | (x & 1);
                x = x >> 1;
            end
            bit_reverse = r;
        end
    endfunction

    // ========================================================================
    // 状态定义
    // ========================================================================
    localparam [3:0]
        S_IDLE       = 4'd0,
        S_LOAD_INIT  = 4'd9,   // 通过同步写端口加载 data_in 到 buf_a
        S_LOAD_GAP   = 4'd10,  // 空闲周期（BRAM 同步写生效 + 设置首地址）
        S_LOAD_GAP2  = 4'd11,  // 额外空闲周期
        S_LOAD_RD    = 4'd1,   // 捕获首元素（BRAM 首地址已在上一状态设置）
        S_LOAD_DATA  = 4'd2,   // 串行读 2*stride 个元素到 pe_data_in
        S_LOAD_TW    = 4'd3,   // 加载 twiddle，触发 PE
        S_WAIT_PE    = 4'd4,   // 等待 PE 完成
        S_WRITE      = 4'd5,   // 串行写 PE 结果
        S_OUTPUT_RD  = 4'd6,   // 串行读结果到 data_out
        S_DONE       = 4'd7;

    reg [3:0] state;
    integer i;

    // ========================================================================
    // 组合逻辑：写使能、写地址、写数据、读数据
    // ========================================================================
    // 写使能、写地址、写数据（全部组合逻辑）
    wire [ADDR_W-1:0] write_addr = block_offset[ADDR_W-1:0] + cnt[ADDR_W-1:0];

    // 顺序寻址：每个 pass 读 2*stride 个连续元素
    // 管道 stride = DIF stride，预变换配对 (data[g], data[g+stride])
    wire [7:0] next_cnt = cnt[7:0] + 1;

    // 下一个源地址（顺序：block_offset + next_cnt）
    wire [ADDR_W-1:0] next_src_addr = block_offset[ADDR_W-1:0] + next_cnt[ADDR_W-1:0];

    // 下一个 pass 的块偏移（组合逻辑）
    wire [7:0] next_block_offset = block_offset + 2 * stride;

    always @(*) begin
        // buf_sel=0: 读 buf_a, 写 buf_b;  buf_sel=1: 读 buf_b, 写 buf_a
        // S_LOAD_INIT: 通过 buf_a 写端口加载初始数据
        we_a = (state == S_LOAD_INIT) || ((state == S_WRITE) && (buf_sel == 1'b1));
        we_b = (state == S_WRITE) && (buf_sel == 1'b0);
        // 写地址
        waddr_a = (state == S_LOAD_INIT) ? cnt[ADDR_W-1:0] : write_addr;
        waddr_b = write_addr;
        // 写数据
        din_a = (state == S_LOAD_INIT) ? data_in[cnt[7:0]] : cur_pe_out;
        din_b = cur_pe_out;
    end

    // 写数据 = pe_data_out[cnt]（组合逻辑）
    reg [MAX_WIDTH-1:0] cur_pe_out;
    always @(*) begin
        case (cnt)
            0:  cur_pe_out = pe_data_out[0];
            1:  cur_pe_out = pe_data_out[1];
            2:  cur_pe_out = pe_data_out[2];
            3:  cur_pe_out = pe_data_out[3];
            4:  cur_pe_out = pe_data_out[4];
            5:  cur_pe_out = pe_data_out[5];
            6:  cur_pe_out = pe_data_out[6];
            7:  cur_pe_out = pe_data_out[7];
            8:  cur_pe_out = pe_data_out[8];
            9:  cur_pe_out = pe_data_out[9];
            10: cur_pe_out = pe_data_out[10];
            11: cur_pe_out = pe_data_out[11];
            12: cur_pe_out = pe_data_out[12];
            13: cur_pe_out = pe_data_out[13];
            14: cur_pe_out = pe_data_out[14];
            15: cur_pe_out = pe_data_out[15];
            default: cur_pe_out = 0;
        endcase
    end

    // 读出数据 = buf_a 或 buf_b
    wire [MAX_WIDTH-1:0] cur_dout = (buf_sel == 1'b0) ? dout_a : dout_b;

    // ========================================================================
    // 主状态机
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            ntt_done     <= 1'b0;
            ntt_valid    <= 1'b0;
            pe_start     <= 1'b0;
            stride       <= 0;
            level_cnt    <= 0;
            N_reg        <= 0;
            radix_reg    <= 0;
            cnt          <= 0;
            buf_sel      <= 1'b0;
            pass_idx     <= 0;
            pass_total   <= 0;
            block_offset <= 0;
            block_idx    <= 0;
            raddr_a      <= 0;
            raddr_b      <= 0;
            for (i = 0; i < MAX_N; i = i + 1) data_out[i] <= 0;
            for (i = 0; i < MAX_RADIX; i = i + 1) pe_data_in[i] <= 0;
            for (i = 0; i < MAX_RADIX/2; i = i + 1) pe_twiddle[i] <= 0;
        end else begin
            pe_start <= 1'b0;

            case (state)
                // =============================================================
                S_IDLE: begin
                    ntt_done  <= 1'b0;
                    ntt_valid <= 1'b0;
                    if (start_ntt) begin
                        $display("NTT_CTRL: IDLE start");
                        for (integer di = 0; di < 8; di = di + 1)
                            $display("  buf_a[%0d] = 0x%064h", di, buf_a_ram.mem[di]);
                        $display("NTT_CTRL: br_table: %0d %0d %0d %0d %0d %0d %0d %0d",
                                 br_table[0], br_table[1], br_table[2], br_table[3],
                                 br_table[4], br_table[5], br_table[6], br_table[7]);
                        N_reg        <= (1 << log2_N);
                        radix_reg    <= radix_mode;
                        stride       <= (1 << log2_N) >> 1;  // 管道 stride = DIF stride，从 N/2 开始递减
                        level_cnt    <= 0;
                        cnt          <= 0;
                        pass_idx     <= 0;
                        // pass_total = (N/2) / stride
                        pass_total   <= ((1 << log2_N) >> 1);
                        block_offset <= 0;
                        block_idx    <= 0;
                        buf_sel      <= 1'b0;

                        // 通过同步写端口加载初始数据到 buf_a
                        $display("NTT_CTRL: data_in[0]=0x%064h data_in[4]=0x%064h",
                                 data_in[0], data_in[4]);
                        state   <= S_LOAD_INIT;
                    end
                end

                // =============================================================
                // 初始数据加载：通过同步写端口将 data_in 写入 buf_a
                // =============================================================
                S_LOAD_INIT: begin
                    // we_a, waddr_a, din_a 由组合逻辑驱动
                    cnt <= cnt + 1;
                    if (cnt + 1 >= N_reg) begin
                        // 加载完成，空闲一周期让 BRAM 同步写生效
                        cnt <= 0;
                        state <= S_LOAD_GAP;
                    end
                end

                S_LOAD_GAP: begin
                    // 空闲多周期，确保同步写完全生效
                    raddr_a <= 0;
                    state <= S_LOAD_GAP2;
                end

                S_LOAD_GAP2: begin
                    // 再等一周期
                    state <= S_LOAD_RD;
                end

                // =============================================================
                // 数据加载：串行读 2*stride 个元素到 pe_data_in
                // 首地址已在上一状态设置
                // =============================================================
                S_LOAD_RD: begin
                    // 首地址已在上一状态设置，BRAM dout 已有效
                    pe_data_in[0] <= cur_dout;
                    // 设置下一个地址
                    if (buf_sel == 1'b0)
                        raddr_a <= block_offset + 1;
                    else
                        raddr_b <= block_offset + 1;
                    cnt <= 0;
                    state <= S_LOAD_DATA;
                end

                S_LOAD_DATA: begin
                    // 捕获当前 dout
                    pe_data_in[cnt + 1] <= cur_dout;

                    // 顺序寻址：每 pass 加载 2*stride 个元素
                    if (next_cnt < 2 * stride - 1) begin
                        if (buf_sel == 1'b0)
                            raddr_a <= block_offset + next_cnt + 1;
                        else
                            raddr_b <= block_offset + next_cnt + 1;
                    end

                    cnt <= cnt + 1;
                    if (next_cnt >= 2 * stride - 1)
                        state <= S_LOAD_TW;
                end

                S_LOAD_TW: begin
                    // 加载 twiddle 因子
                    for (i = 0; i < MAX_RADIX/2; i = i + 1) begin
                        if (i < stride)
                            pe_twiddle[i] <= twiddle_full[((block_idx * (N_reg >> 1) + i[7:0]) * (N_reg / (2 * stride))) % (MAX_N/2)];
                        else
                            pe_twiddle[i] <= 0;
                    end

                    // 根据 stride 设置 radix_mode，使后变换等待正确数量的子核
                    // stride=1 → radix-2 (2'b00), stride=2 → radix-4 (2'b01),
                    // stride=4 → radix-8 (2'b10), stride=8+ → radix-16 (2'b11)
                    if (stride <= 1)
                        radix_reg <= 2'b00;
                    else if (stride <= 2)
                        radix_reg <= 2'b01;
                    else if (stride <= 4)
                        radix_reg <= 2'b10;
                    else
                        radix_reg <= 2'b11;

                    pe_start <= 1'b1;
                    state    <= S_WAIT_PE;
                end

                // =============================================================
                // 等待 PE 管线完成
                // =============================================================
                S_WAIT_PE: begin
                    if (pe_result_valid) begin
                        $display("NTT_CTRL: PE done pass=%0d/%0d stride=%0d",
                                 pass_idx, pass_total, stride);
                        $display("  pe_out[0]=0x%064h [1]=0x%064h [2]=0x%064h [3]=0x%064h",
                                 pe_data_out[0], pe_data_out[1], pe_data_out[2], pe_data_out[3]);

                        cnt <= 0;
                        // 不预读：当前 pass 的首地址已在上一状态设置
                        // S_WRITE[0] 将用当前地址读出本 pass 首元素数据
                        state <= S_WRITE;
                    end
                end

                // =============================================================
                // 串行写回 PE 结果 + 预读下个 pass
                // =============================================================
                S_WRITE: begin
                    // 写地址和写数据由组合逻辑驱动（write_addr, cur_pe_out）
                    // cnt 递增（非阻塞）
                    cnt <= cnt + 1;

                    if (next_cnt >= 2 * stride) begin
                        // 本 pass 写回完成（写了 2*stride 个元素）
                        if (pass_idx < pass_total - 1) begin
                            // 更多 pass
                            pass_idx     <= pass_idx + 1;
                            block_offset <= next_block_offset;
                            block_idx    <= block_idx + 1;
                            cnt          <= 0;
                            // 设置下 pass 首地址
                            if (buf_sel == 1'b0)
                                raddr_a <= next_block_offset;
                            else
                                raddr_b <= next_block_offset;
                            state <= S_LOAD_RD;
                        end else begin
                            // 当前级完成
                            buf_sel      <= ~buf_sel;
                            stride       <= stride >> 1;
                            level_cnt    <= level_cnt + 1;
                            pass_idx     <= 0;
                            block_offset <= 0;
                            block_idx    <= 0;
                            block_idx    <= 0;
                            cnt          <= 0;

                            if (stride > 1) begin
                                // pass_total = (N/2) / (stride/2)
                                pass_total <= (N_reg >> 1) / (stride >> 1);
                                // 设置下一级首地址（使用新 buf_sel：已取反）
                                if (buf_sel == 1'b0)
                                    raddr_b <= 0;  // 新 buf_sel=1 读 buf_b
                                else
                                    raddr_a <= 0;  // 新 buf_sel=0 读 buf_a
                                state <= S_LOAD_RD;
                            end else begin
                                // 全部级完成，输出结果
                                // buf_sel 已翻转，结果在另一个缓冲
                                if (buf_sel == 1'b0)
                                    raddr_a <= 0;
                                else
                                    raddr_b <= 0;
                                state <= S_OUTPUT_RD;
                            end
                        end
                    end
                end

                // =============================================================
                // 输出：串行读结果到 data_out
                // =============================================================
                S_OUTPUT_RD: begin
                    // cur_dout 来自结果缓冲（上周期设置的地址）
                    data_out[cnt] <= cur_dout;

                    // 设置下一个读地址
                    if (cnt + 1 < N_reg) begin
                        if (buf_sel == 1'b0)
                            raddr_a <= cnt[ADDR_W-1:0] + 1;
                        else
                            raddr_b <= cnt[ADDR_W-1:0] + 1;
                    end

                    cnt <= cnt + 1;

                    if (cnt + 1 >= N_reg) begin
                        ntt_done  <= 1'b1;
                        ntt_valid <= 1'b1;
                        state     <= S_DONE;
                    end
                end

                // =============================================================
                S_DONE: begin
                    ntt_done  <= 1'b1;
                    ntt_valid <= 1'b1;
                    if (!start_ntt)
                        state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
