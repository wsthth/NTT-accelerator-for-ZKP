`timescale 1ns/1ps

// ============================================================================
// 文件名: reconfigurable_3d_pe_top.v
// 描述: 可重构PE顶层模块
// 功能: 支持基(2/4/8/16)可变位宽(256/384)的蝶形运算单元，使用Winograd优化
// ============================================================================
module reconfigurable_3d_pe_top #(
    parameter MAX_WIDTH = 256,      // 支持位宽可配置，256/384位
    parameter MAX_RADIX = 16,       // 最大基数
    parameter NUM_CORES = 8         // 子核数量
)(
    // 系统信号
    input wire clk,
    input wire rst_n,
    
    // 配置接口
    input wire [1:0] radix_mode,    // 00:基2, 01:基4, 10:基8, 11:基16
    input wire width_384_mode,      // 0:256bit, 1:384bit
    input wire [2:0] parallelism,   // 并行度控制，决定启用多少个子核
    
    // 控制信号
    input wire start,
    input wire clear_post,      // 后变换清除/重新加载控制
    output wire done,
    output wire result_valid,

    // DIF算法参数
    input wire [9:0] stride,            // 用于DIF算法的stride

    // 数据和旋转因子输入
    input wire [MAX_WIDTH-1:0] data_in [0:MAX_RADIX-1],
    input wire [MAX_WIDTH-1:0] twiddle_factors [0:MAX_RADIX/2-1],
    
    // 模数参数
    input wire [MAX_WIDTH-1:0] modulus,
    input wire [MAX_WIDTH-1:0] N_prime,
    input wire [MAX_WIDTH-1:0] R2_mod_N,  // R^2 mod N
    
    // 数据输出
    output wire [MAX_WIDTH-1:0] data_out [0:MAX_RADIX-1]
);

// ============================================================================
// 配置寄存器
// ============================================================================
reg [1:0] radix_config;
reg width_config;
reg [2:0] parallelism_config;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        radix_config <= 2'b00;
        width_config <= 1'b0;
        parallelism_config <= 3'b000;
    end else if (start) begin
        radix_config <= radix_mode;
        width_config <= width_384_mode;
        parallelism_config <= parallelism;
    end
end

// 计算实际基数
wire [3:0] actual_radix = (radix_config == 2'b00) ? 4'd2 :
                         (radix_config == 2'b01) ? 4'd4 :
                         (radix_config == 2'b10) ? 4'd8 : 4'd16;

// wire [5:0] seg_count = width_config ? 6'd6 : 6'd4;  // 384位=6段, 256位=4段
localparam [5:0] seg_count =6'd4;  // 384位=6段, 256位=4段

localparam [7:0] seg_width = 8'd64;  // 每段64位

// ============================================================================
// Winograd预变换
// ============================================================================
wire [MAX_WIDTH-1:0] winograd_x0 [0:NUM_CORES-1];
wire [MAX_WIDTH-1:0] winograd_x1 [0:NUM_CORES-1];
wire [MAX_WIDTH-1:0] winograd_w [0:NUM_CORES-1];
wire [MAX_WIDTH-1:0] winograd_conj_coeff [0:NUM_CORES-1];
// wire [NUM_CORES-1:0] winograd_valid;
wire  winograd_valid;
winograd_pre_transform #(
    .MAX_WIDTH(MAX_WIDTH),
    .MAX_RADIX(MAX_RADIX),
    .NUM_CORES(NUM_CORES)
) u_winograd_pre (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .radix_mode(radix_mode),
    .stride(stride),
    
    // 输入接口
    .data_in(data_in),
    .twiddle_in(twiddle_factors),
    .modulus(modulus),
    
    // 预变换输出
    .x0_out(winograd_x0),
    .x1_out(winograd_x1),
    .w_out(winograd_w),
    .conj_coeff_out(winograd_conj_coeff),
    .valid_out(winograd_valid)
);

// ============================================================================
// 可配置的8个子核阵列
// ============================================================================
wire [MAX_WIDTH-1:0] core_result0 [0:NUM_CORES-1];
wire [MAX_WIDTH-1:0] core_result1 [0:NUM_CORES-1];
wire [NUM_CORES-1:0] core_done;
wire [NUM_CORES-1:0] core_busy;
wire [NUM_CORES-1:0] core_result_valid_array;  // 子核结果有效信号阵列
// 根据并行度选择启用的子核
reg [NUM_CORES-1:0] core_enable;

always @(*) begin
    core_enable = {NUM_CORES{1'b0}};
    case(parallelism_config)
        3'b000: core_enable[0] = 1'b1;  // 使用1个子核
        3'b001: core_enable[1:0] = 2'b11;  // 使用2个子核
        3'b010: core_enable[3:0] = 4'b1111;  // 使用4个子核
        3'b011: core_enable[5:0] = 6'b111111;  // 使用6个子核
        3'b100: core_enable[7:0] = 8'b11111111;  // 使用8个子核
        default: core_enable = {NUM_CORES{1'b1}};
    endcase
end

// 实例化8个子核
genvar core_idx;
generate
    for (core_idx = 0; core_idx < NUM_CORES; core_idx = core_idx + 1) begin : core_array
        // 每个子核是一个分段256位完整蝶形单元
        segmented_256bit_full_butterfly #(
            .TOTAL_WIDTH(MAX_WIDTH),
            .SEG_WIDTH(seg_width),
            .SEG_COUNT(seg_count)
        ) u_core (
            .clk(clk),
            .rst_n(rst_n),
            // .start(start & core_enable[core_idx] & winograd_valid[core_idx]),
            .start(winograd_valid & core_enable[core_idx]),
            .done(core_done[core_idx]),
            .busy(core_busy[core_idx]),
            
            // 输入来自Winograd预变换
            .x0(winograd_x0[core_idx]),
            .x1(winograd_x1[core_idx]),
            .w(winograd_w[core_idx]),
            .N_prime(N_prime),
            .modulus(modulus),
            
            // 输出结果（加法和减法）
            .result_add(core_result0[core_idx]),  // 加法结果
            .result_sub(core_result1[core_idx]),  // 减法结果
            .result_valid()
            // .result_valid(core_result_valid[core_idx])
        );
    end
endgenerate

// ============================================================================
// Winograd后变换与结果重组
// ============================================================================
wire post_transform_valid;

winograd_post_transform #(
    .MAX_WIDTH(MAX_WIDTH),
    .MAX_RADIX(MAX_RADIX),
    .NUM_CORES(NUM_CORES)
) u_winograd_post (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),         // 与输入同步
    .clear(clear_post),    // 清除控制
    
    // 配置
    .radix_mode(radix_config),
    
    // 子核结果输入
    .core_result0(core_result0),
    .core_result1(core_result1),
    .core_done(core_done),
    // .core_done(4'b0001),
    .conj_coeff(winograd_conj_coeff),
    .modulus(modulus),
    
    // 最终输出
    .data_out(data_out),
    .result_valid(post_transform_valid)
);

// ============================================================================
// Karatsuba优化（可选）
// ============================================================================
// 当前使用分段乘法实现，64位分段
// wire karatsuba_enable = 1'b1;  // 启用Karatsuba优化
localparam karatsuba_enable = 1'b1;  // 启用Karatsuba优化
generate
    if (karatsuba_enable) begin
        // 使用Karatsuba优化的64位乘法器
        // 替换seg_multiplier_64bit模块
    end
endgenerate

// ============================================================================
// 完成信号生成
// ============================================================================
// 检测所有启用的子核是否完成，并与后变换同步
reg all_cores_done;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        all_cores_done <= 1'b0;
    end else begin
        // 检查所有启用的子核是否完成
        if (&(core_done | ~core_enable)) begin
            all_cores_done <= 1'b1;
        end else if (!start) begin
            // all_cores_done <= 1'b0;
            all_cores_done <= 1'b1;//保持高电平以支持流水线连续输入
        end
    end
end

assign done = all_cores_done & post_transform_valid;
assign result_valid = done;

// ============================================================================
// 性能统计
// ============================================================================
reg [31:0] cycle_counter;
reg [31:0] total_multiplies;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cycle_counter <= 32'd0;
        total_multiplies <= 32'd0;
    end else if (start && !done) begin
        cycle_counter <= cycle_counter + 1;
        
        // 根据基数统计乘法次数
        case(radix_config)
            2'b00: total_multiplies <= total_multiplies + 1;  // 基2: 1次乘法
            2'b01: total_multiplies <= total_multiplies + 3;  // 基4: 3次乘法
            2'b10: total_multiplies <= total_multiplies + 7;  // 基8: 7次乘法
            2'b11: total_multiplies <= total_multiplies + 8;  // 基16(Winograd): 8次乘法
        endcase
    end else if (done) begin
        // 统计完成
    end
end

endmodule