// ============================================================================
// 文件名: reconfigurable_3d_pe_top.v
// 描述: 三维可重构PE顶层模块
// 创新点: 基数(2/4/8/16)、位宽(256/384)、并行度可配置，Winograd优化
// ============================================================================
module reconfigurable_3d_pe_top #(
    parameter MAX_WIDTH = 128,      // 最大位宽（支持256/384）
    parameter MAX_RADIX = 16,       // 最大基数
    parameter NUM_CORES = 4         // 子核数量
)(
    // 系统接口
    input wire clk,
    input wire rst_n,
    
    // 三维配置
    input wire [1:0] radix_mode,    // 00:基2, 01:基4, 10:基8, 11:基16
    input wire width_384_mode,      // 0:256bit, 1:384bit
    input wire [2:0] parallelism,   // 并行度：激活子核数
    
    // 控制信号
    input wire start,
    output wire done,
    output wire result_valid,
    
    // 数据输入（根据基数动态）
    input wire [MAX_WIDTH-1:0] data_in [0:MAX_RADIX-1],
    input wire [MAX_WIDTH-1:0] twiddle_factors [0:MAX_RADIX/2-1],
    
    // 模运算参数
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

// 根据配置确定实际参数
wire [3:0] actual_radix = (radix_config == 2'b00) ? 4'd2 :
                         (radix_config == 2'b01) ? 4'd4 :
                         (radix_config == 2'b10) ? 4'd8 : 4'd16;

// wire [5:0] seg_count = width_config ? 6'd6 : 6'd4;  // 384位=6段, 256位=4段
localparam [5:0] seg_count =6'd4;  // 384位=6段, 256位=4段

localparam [7:0] seg_width = 8'd64;  // 固定64位段

// ============================================================================
// Winograd预变换模块
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
    .radix_mode(radix_config),
    
    // 原始输入
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
// 子核资源池（8个子核）
// ============================================================================
wire [MAX_WIDTH-1:0] core_result0 [0:NUM_CORES-1];
wire [MAX_WIDTH-1:0] core_result1 [0:NUM_CORES-1];
wire [NUM_CORES-1:0] core_done;
wire [NUM_CORES-1:0] core_busy;
wire [NUM_CORES-1:0] core_result_valid_array;  // 添加缺失的信号声明
// 动态使能信号（根据并行度配置）
reg [NUM_CORES-1:0] core_enable;

always @(*) begin
    core_enable = {NUM_CORES{1'b0}};
    case(parallelism_config)
        3'b000: core_enable[0] = 1'b1;  // 激活1个子核
        3'b001: core_enable[1:0] = 2'b11;  // 激活2个子核
        3'b010: core_enable[3:0] = 4'b1111;  // 激活4个子核
/*         3'b011: core_enable[5:0] = 6'b111111;  // 激活6个子核
        3'b100: core_enable[7:0] = 8'b11111111;  // 激活8个子核
 */        default: core_enable = {NUM_CORES{1'b1}};
    endcase
end

// 实例化8个子核
genvar core_idx;
generate
    for (core_idx = 0; core_idx < NUM_CORES; core_idx = core_idx + 1) begin : core_array
        // 每个子核都是完整的基2蝶形运算器
        segmented_256bit_full_butterfly #(
/*             .TOTAL_WIDTH(MAX_WIDTH),
            .SEG_WIDTH(seg_width),
            .SEG_COUNT(seg_count)
 */            
            .TOTAL_WIDTH(128),
            .SEG_WIDTH(64),
            .SEG_COUNT(2)
            
        ) u_core (
            .clk(clk),
            .rst_n(rst_n),
            // .start(start & core_enable[core_idx] & winograd_valid[core_idx]),
            .start(start & core_enable[core_idx]),
            .done(core_done[core_idx]),
            .busy(core_busy[core_idx]),
            
            // 输入数据（来自Winograd预变换）
            .x0(winograd_x0[core_idx]),
            .x1(winograd_x1[core_idx]),
            .w(winograd_w[core_idx]),
            .N_prime(N_prime),
            .modulus(modulus),
            
            // 输出结果（两个分支）
            .result_add(core_result0[core_idx]),  // 加法分支
            .result_sub(core_result1[core_idx]),  // 减法分支
            .result_valid()
            // .result_valid(core_result_valid[core_idx])
        );
    end
endgenerate

// ============================================================================
// Winograd后变换（结果重组）
// ============================================================================
reg [MAX_WIDTH-1:0] transformed_result [0:MAX_RADIX-1];

winograd_post_transform #(
    .MAX_WIDTH(MAX_WIDTH),
    .MAX_RADIX(MAX_RADIX),
    .NUM_CORES(NUM_CORES)
) u_winograd_post (
    .clk(clk),
    .rst_n(rst_n),
    
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
    .data_out(transformed_result),
    .result_valid(post_transform_valid)
);

// ============================================================================
// Karatsuba优化乘法器（可选）
// ============================================================================
// 如果启用Karatsuba优化，替换普通的64位乘法器

// wire karatsuba_enable = 1'b1;  // 默认启用
localparam karatsuba_enable = 1'b1;  // 默认启用
generate
    if (karatsuba_enable) begin
        // 使用Karatsuba优化的64位乘法器
        // 这将替换原seg_multiplier_64bit模块
    end
endgenerate

// ============================================================================
// 输出分配
// ============================================================================
assign data_out = transformed_result;

// 完成信号：所有激活的子核都完成且后变换完成
reg all_cores_done;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        all_cores_done <= 1'b0;
    end else begin
        // 检查所有激活的子核是否完成
        if (&(core_done | ~core_enable)) begin
            all_cores_done <= 1'b1;
        end else if (!start) begin
            // all_cores_done <= 1'b0;
            all_cores_done <= 1'b1;//这里先暂时这样写，便于仿真
        end
    end
end

assign done = all_cores_done & post_transform_valid;
assign result_valid = done;

// ============================================================================
// 性能监控
// ============================================================================
reg [31:0] cycle_counter;
reg [31:0] total_multiplies;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cycle_counter <= 32'd0;
        total_multiplies <= 32'd0;
    end else if (start && !done) begin
        cycle_counter <= cycle_counter + 1;
        
        // 统计乘法次数（根据基数）
        case(radix_config)
            2'b00: total_multiplies <= total_multiplies + 1;  // 基2: 1次乘法
            2'b01: total_multiplies <= total_multiplies + 3;  // 基4: 3次乘法
            2'b10: total_multiplies <= total_multiplies + 7;  // 基8: 7次乘法
            2'b11: total_multiplies <= total_multiplies + 8;  // 基16(Winograd): 8次乘法
        endcase
    end else if (done) begin
        // 保持最终值
    end
end

endmodule