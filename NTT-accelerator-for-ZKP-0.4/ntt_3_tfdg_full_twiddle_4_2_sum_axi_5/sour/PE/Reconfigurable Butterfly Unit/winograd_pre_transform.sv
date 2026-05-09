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
                        // 根据基数确定需要计算的组数
                        case (radix_mode)
                            2'b00: total_groups <= 1;   // 基2
                            2'b01: total_groups <= 2;   // 基4
                            2'b10: total_groups <= 4;   // 基8
                            2'b11: total_groups <= 8;   // 基16
                            default: total_groups <= 0;
                        endcase
                        group_cnt <= 0;
                        mod_reg <= modulus;
                        state <= PREPARE;
                    end
                end

                PREPARE: begin
                    // 准备当前组的输入数据索引
                    case (radix_mode)
                        2'b00: begin
                            idx1 <= 0;
                            idx2 <= 1;
                        end
                        2'b01: begin
                            // 组0: (0,2), (1,3); 组1: (0,2), (1,3) 但用减法
                            if (group_cnt == 0) begin
                                idx1 <= 0; idx2 <= 2;
                            end else begin
                                idx1 <= 0; idx2 <= 2;
                            end
                        end
                        2'b10, 2'b11: begin
                            // 对称对: (g, 7-g) 或 (g, 15-g)
                            idx1 <= group_cnt;
                            idx2 <= (radix_mode == 2'b10) ? (7 - group_cnt) : (15 - group_cnt);
                        end
                    endcase
                    state <= CALC_GROUP;
                end

                CALC_GROUP: begin
                    // 只使用一组加法器/减法器，依次计算各组
                    case (radix_mode)
                        2'b00: begin
                            // 基2: 直接传递，无需运算
                            group_x0[0] <= data_in[0];
                            group_x1[0] <= data_in[1];
                            group_w[0]  <= twiddle_in[0];
                            group_conj[0] <= 0;
                        end

                        2'b01: begin
                            if (group_cnt == 0) begin
                                // 组0: 加法
                                group_x0[0] <= mod_add(data_in[0], data_in[2], mod_reg);
                                group_x1[0] <= mod_add(data_in[1], data_in[3], mod_reg);
                                group_w[0]  <= twiddle_in[0];
                                group_conj[0] <= twiddle_in[1];   // 简化：共轭 = 另一个 twiddle
                            end else begin
                                // 组1: 减法
                                group_x0[1] <= mod_sub(data_in[0], data_in[2], mod_reg);
                                group_x1[1] <= mod_sub(data_in[1], data_in[3], mod_reg);
                                group_w[1]  <= twiddle_in[1];
                                group_conj[1] <= twiddle_in[0];
                            end
                        end

                        2'b10, 2'b11: begin
                            // 基8/16：每组计算加法和减法，直接使用当前索引的数据
                            group_x0[group_cnt] <= mod_add(data_in[idx1], data_in[idx2], mod_reg);
                            group_x1[group_cnt] <= mod_sub(data_in[idx1], data_in[idx2], mod_reg);
                            group_w[group_cnt]  <= twiddle_in[group_cnt];
                            // 共轭系数简化（实际应为 twiddle_in[group_cnt] 的模逆）
                            group_conj[group_cnt] <= twiddle_in[group_cnt];
                        end
                    endcase

                    // 推进组索引
                    if (group_cnt == total_groups - 1)
                        state <= APPLY_OUTPUT;
                    else begin
                        group_cnt <= group_cnt + 1;
                        state <= PREPARE;   // 准备下一组
                    end
                end

                APPLY_OUTPUT: begin
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
                    if (!start) begin
                        state <= IDLE;
                        valid_out <= 1'b0;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
