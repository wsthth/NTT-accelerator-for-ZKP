// ============================================================================
// 文件名: winograd_pre_transform_opt.v
// 描述: 低LUT占用的Winograd预变换模块，采用流水线和资源共享
// ============================================================================
module winograd_pre_transform #(
    parameter MAX_WIDTH = 384,
    parameter MAX_RADIX = 16,
    parameter NUM_CORES = 8
)(
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [1:0] radix_mode,
    input wire [7:0] stride,                    // DIF级的stride参数
    input wire [MAX_WIDTH-1:0] data_in [0:MAX_RADIX-1],
    input wire [MAX_WIDTH-1:0] twiddle_in [0:MAX_RADIX/2-1],
    input wire [MAX_WIDTH-1:0] modulus,
    output reg [MAX_WIDTH-1:0] x0_out [0:NUM_CORES-1],
    output reg [MAX_WIDTH-1:0] x1_out [0:NUM_CORES-1],
    output reg [MAX_WIDTH-1:0] w_out [0:NUM_CORES-1],
    output reg [MAX_WIDTH-1:0] conj_coeff_out [0:NUM_CORES-1],
    output reg valid_out
);

    // 状态机
    reg [2:0] state;
    localparam IDLE          = 3'd0,
               PREPARE       = 3'd1,
               CALC_GROUP    = 3'd2,
               APPLY_OUTPUT  = 3'd3,
               DONE          = 3'd4;

    // 分组存储（寄存器数组）
    reg [MAX_WIDTH-1:0] group_x0 [0:7];
    reg [MAX_WIDTH-1:0] group_x1 [0:7];
    reg [MAX_WIDTH-1:0] group_w  [0:7];
    reg [MAX_WIDTH-1:0] group_conj[0:7];

    // 控制变量
    reg [2:0] group_cnt;        // 当前计算组索引 (0~7)
    reg [2:0] total_groups;     // 根据基数确定的总组数
    reg [3:0] idx1, idx2;       // 输入数据索引

    // 模加/减法组合逻辑（资源共享）
    wire [MAX_WIDTH-1:0] sum_ab, diff_ab;
    reg  [MAX_WIDTH-1:0] a_reg, b_reg;      // 临时寄存器，减少组合路径
    reg  [MAX_WIDTH-1:0] mod_reg;
    
    // 模加法：返回 (a+b) mod mod
    function [MAX_WIDTH-1:0] mod_add;
        input [MAX_WIDTH-1:0] a, b, mod;
        reg [MAX_WIDTH:0] tmp;
        begin
            tmp = a + b;
            mod_add = (tmp >= mod) ? (tmp - mod) : tmp;
        end
    endfunction

    // 模减法：返回 (a-b) mod mod
    function [MAX_WIDTH-1:0] mod_sub;
        input [MAX_WIDTH-1:0] a, b, mod;
        reg [MAX_WIDTH-1:0] diff;
        begin
            if (a >= b)
                diff = a - b;
            else
                diff = a + mod - b;
            mod_sub = (diff >= mod) ? (diff - mod) : diff;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            valid_out <= 1'b0;
            group_cnt <= 0;
            total_groups <= 0;
            a_reg <= 0;
            b_reg <= 0;
            mod_reg <= 0;
            for (integer i = 0; i < NUM_CORES; i = i + 1) begin
                x0_out[i] <= {MAX_WIDTH{1'b0}};
                x1_out[i] <= {MAX_WIDTH{1'b0}};
                w_out[i] <= {MAX_WIDTH{1'b0}};
                conj_coeff_out[i] <= {MAX_WIDTH{1'b0}};
            end
            for (integer i = 0; i < 8; i = i + 1) begin
                group_x0[i] <= 0;
                group_x1[i] <= 0;
                group_w[i]  <= 0;
                group_conj[i] <= 0;
            end
        end else begin
            case (state)
                IDLE: begin
                    valid_out <= 1'b0;
                    if (start) begin
                        $display("PRE_XFORM: start stride=%0d radix_mode=%b", stride, radix_mode);
                        // 总组数 = stride（每个子核一对数据）
                        // 受限于子核数 NUM_CORES
                        if (stride <= NUM_CORES)
                            total_groups <= stride;
                        else
                            total_groups <= NUM_CORES;
                        group_cnt <= 0;
                        mod_reg <= modulus;
                        state <= PREPARE;
                    end
                end

                PREPARE: begin
                    // 准备当前组的输入数据索引
                    // 配对: (data[group_cnt], data[group_cnt + stride])
                    idx1 <= group_cnt;
                    idx2 <= group_cnt + stride;
                    state <= CALC_GROUP;
                end

                CALC_GROUP: begin
                    // 通用路由：配对 (data[idx1], data[idx2]) 送入子核 group_cnt
                    // 子核计算 DIF 蝶形: add = x0+x1, sub = (x0-x1)*w
                    $display("PRE_XFORM: CALC g=%0d idx1=%0d idx2=%0d data[%0d]=0x%064h data[%0d]=0x%064h",
                             group_cnt, idx1, idx2,
                             idx1, data_in[idx1], idx2, data_in[idx2]);
                    group_x0[group_cnt] <= data_in[idx1];
                    group_x1[group_cnt] <= data_in[idx2];
                    group_w[group_cnt]  <= twiddle_in[group_cnt];
                    group_conj[group_cnt] <= 0;

                    // 推进组索引
                    if (group_cnt == total_groups - 1)
                        state <= APPLY_OUTPUT;
                    else begin
                        group_cnt <= group_cnt + 1;
                        state <= PREPARE;   // 准备下一组
                    end
                end

                APPLY_OUTPUT: begin
                    $display("PRE_XFORM: APPLY x0[0]=0x%064h x1[0]=0x%064h w[0]=0x%064h",
                             group_x0[0], group_x1[0], group_w[0]);
                    $display("PRE_XFORM: APPLY x0[1]=0x%064h x1[1]=0x%064h",
                             group_x0[1], group_x1[1]);
                    // 将计算好的分组结果分配给各个子核
                    for (integer i = 0; i < NUM_CORES; i = i + 1) begin
                        if (i < total_groups) begin
                            x0_out[i] <= group_x0[i];
                            x1_out[i] <= group_x1[i];
                            w_out[i]  <= group_w[i];
                            conj_coeff_out[i] <= group_conj[i];
                        end else begin
                            x0_out[i] <= 0;
                            x1_out[i] <= 0;
                            w_out[i]  <= 0;
                            conj_coeff_out[i] <= 0;
                        end
                    end
                    state <= DONE;
                end

                DONE: begin
                    valid_out <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
