// ============================================================================
// 文件名: winograd_pre_transform.v
// 描述: Winograd预变换模块，实现对称分组优化
// 创新点: 将高基数蝶形分解为对称组，减少乘法次数
// ============================================================================
module winograd_pre_transform #(
    parameter MAX_WIDTH = 384,
    parameter MAX_RADIX = 16,
    parameter NUM_CORES = 8
)(
    // 系统接口
    input wire clk,
    input wire rst_n,
    input wire start,
    
    // 配置
    input wire [1:0] radix_mode,
    
    // 原始输入
    input wire [MAX_WIDTH-1:0] data_in [0:MAX_RADIX-1],
    input wire [MAX_WIDTH-1:0] twiddle_in [0:MAX_RADIX/2-1],
    input wire [MAX_WIDTH-1:0] modulus,
    
    // 预变换输出（每个子核的输入）
    output reg [MAX_WIDTH-1:0] x0_out [0:NUM_CORES-1],
    output reg [MAX_WIDTH-1:0] x1_out [0:NUM_CORES-1],
    output reg [MAX_WIDTH-1:0] w_out [0:NUM_CORES-1],
    output reg [MAX_WIDTH-1:0] conj_coeff_out [0:NUM_CORES-1],
    output reg valid_out
);

// ============================================================================
// 内部状态机
// ============================================================================
reg [2:0] state;
localparam [2:0]
    IDLE = 3'd0,
    CALC_GROUPS = 3'd1,
    APPLY_TRANSFORM = 3'd2,
    OUTPUT_READY = 3'd3;

// ============================================================================
// 根据基数进行对称分组
// ============================================================================
reg [MAX_WIDTH-1:0] group_x0 [0:7];  // 每组预变换后的x0
reg [MAX_WIDTH-1:0] group_x1 [0:7];  // 每组预变换后的x1
reg [MAX_WIDTH-1:0] group_w [0:7];   // 每组对应的旋转因子
reg [MAX_WIDTH-1:0] group_conj [0:7]; // 每组共轭系数

// 辅助函数：模加法（不使用%）
function automatic [MAX_WIDTH-1:0] mod_add;
    input [MAX_WIDTH-1:0] a;
    input [MAX_WIDTH-1:0] b;
    input [MAX_WIDTH-1:0] mod;
    reg [MAX_WIDTH:0] sum;  // 扩展1位用于检测溢出
    begin
        sum = a + b;
        if (sum >= mod) begin
            mod_add = sum - mod;
        end else begin
            mod_add = sum;
        end
    end
endfunction

// 辅助函数：模减法（不使用%）
function automatic [MAX_WIDTH-1:0] mod_sub;
    input [MAX_WIDTH-1:0] a;
    input [MAX_WIDTH-1:0] b;
    input [MAX_WIDTH-1:0] mod;
    reg [MAX_WIDTH-1:0] diff;
    begin
        if (a >= b) begin
            diff = a - b;
        end else begin
            diff = a + mod - b;  // 等价于 (a - b + mod)
        end
        // 确保结果在模范围内
        if (diff >= mod) begin
            diff = diff - mod;
        end
        mod_sub = diff;
    end
endfunction

// 辅助函数：模取反（用于计算a的模负数）
function automatic [MAX_WIDTH-1:0] mod_neg;
    input [MAX_WIDTH-1:0] a;
    input [MAX_WIDTH-1:0] mod;
    begin
        if (a == 0) begin
            mod_neg = 0;
        end else begin
            mod_neg = mod - a;
        end
    end
endfunction

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
        valid_out <= 1'b0;
        for (integer i = 0; i < NUM_CORES; i = i + 1) begin
            x0_out[i] <= {MAX_WIDTH{1'b0}};
            x1_out[i] <= {MAX_WIDTH{1'b0}};
            w_out[i] <= {MAX_WIDTH{1'b0}};
            conj_coeff_out[i] <= {MAX_WIDTH{1'b0}};
        end
    end else begin
        case(state)
            IDLE: begin
                if (start) begin
                    state <= CALC_GROUPS;
                    valid_out <= 1'b0;
                end
            end
            
            CALC_GROUPS: begin
                    case(radix_mode)
                        2'b00: begin  // 基2：不分组，直接使用
                            group_x0[0] <= data_in[0];
                            group_x1[0] <= data_in[1];
                            group_w[0] <= twiddle_in[0];
                            group_conj[0] <= {MAX_WIDTH{1'b0}};  // 基2无共轭
                        end
                        
                        2'b01: begin  // 基4：分为2组
                            // 组0: (w₀, w₃)，w₃是w₁的模逆
                            group_x0[0] <= mod_add(data_in[0], data_in[2], modulus);
                            group_x1[0] <= mod_add(data_in[1], data_in[3], modulus);
                            group_w[0] <= twiddle_in[0];  // w0
                            group_conj[0] <= calculate_conjugate(twiddle_in[1], modulus);  // w3
                            
                            // 组1: (w₁, w₂)，w₂是w₀的模逆
                            group_x0[1] <= mod_sub(data_in[0], data_in[2], modulus);
                            group_x1[1] <= mod_sub(data_in[1], data_in[3], modulus);
                            group_w[1] <= twiddle_in[1];  // w1
                            group_conj[1] <= calculate_conjugate(twiddle_in[0], modulus);  // w2
                        end
                        
                        2'b10: begin  // 基8：分为4组
                            for (integer g = 0; g < 4; g = g + 1) begin
                                integer idx1 = g;
                                integer idx2 = 7 - g;
                                
                                group_x0[g] <= mod_add(data_in[idx1], data_in[idx2], modulus);
                                group_x1[g] <= mod_sub(data_in[idx1], data_in[idx2], modulus);
                                group_w[g] <= twiddle_in[g];  // w0~w3
                                group_conj[g] <= calculate_conjugate(twiddle_in[g], modulus);  // w7~w4
                            end
                        end
                        
                        2'b11: begin  // 基16：分为8组
                            for (integer g = 0; g < 8; g = g + 1) begin
                                integer idx1 = g;
                                integer idx2 = 15 - g;
                                
                                group_x0[g] <= mod_add(data_in[idx1], data_in[idx2], modulus);
                                group_x1[g] <= mod_sub(data_in[idx1], data_in[idx2], modulus);
                                group_w[g] <= twiddle_in[g];  // w0~w7
                                group_conj[g] <= calculate_conjugate(twiddle_in[g], modulus);  // w15~w8
                            end
                        end
                    endcase
                    
                    state <= APPLY_TRANSFORM;
                end            
            APPLY_TRANSFORM: begin
                // 将分组结果分配给各子核
                for (integer i = 0; i < NUM_CORES; i = i + 1) begin
                    if (i < (1 << (radix_mode + 1)) / 2) begin  // 根据基数确定需要的组数
                        x0_out[i] <= group_x0[i];
                        x1_out[i] <= group_x1[i];
                        w_out[i] <= group_w[i];
                        conj_coeff_out[i] <= group_conj[i];
                    end else begin
                        // 多余的子核输入置零
                        x0_out[i] <= {MAX_WIDTH{1'b0}};
                        x1_out[i] <= {MAX_WIDTH{1'b0}};
                        w_out[i] <= {MAX_WIDTH{1'b0}};
                        conj_coeff_out[i] <= {MAX_WIDTH{1'b0}};
                    end
                end
                
                state <= OUTPUT_READY;
                valid_out <= 1'b1;
            end
            
            OUTPUT_READY: begin
                if (!start) begin
                    state <= IDLE;
                    valid_out <= 1'b0;
                end
            end
        endcase
    end
end

// ============================================================================
// 共轭计算函数
// ============================================================================
function automatic [MAX_WIDTH-1:0] calculate_conjugate;
    input [MAX_WIDTH-1:0] w;
    input [MAX_WIDTH-1:0] modulus;
    begin
        // 计算w的共轭（模逆）
        // 实际实现可能需要模逆运算或查表
        // 这里简化处理，实际应用中需要预计算
        calculate_conjugate = modular_inverse(w, modulus);
    end
endfunction

// 模逆函数（简化表示，实际需要实现或预计算）
function automatic [MAX_WIDTH-1:0] modular_inverse;
    input [MAX_WIDTH-1:0] a;
    input [MAX_WIDTH-1:0] modulus;
    reg [MAX_WIDTH-1:0] result;
    begin
        // 实际实现需要使用扩展欧几里得算法
        // 这里返回一个简化值
        modular_inverse = a;  // 简化处理
    end
endfunction

endmodule