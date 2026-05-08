// ============================================================================
// 文件名: reconfigurable_3d_pe_top.v
// 描述: 三维可重构PE顶层模块（已修改为扁平总线，支持AXI封装）
// ============================================================================
module reconfigurable_3d_pe_top #(
    parameter MAX_WIDTH = 128,      // 最大位宽
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
    
    // ====================== 【修改 1】扁平总线 ======================
    input wire [MAX_WIDTH*MAX_RADIX - 1:0] data_in_flat,
    input wire [MAX_WIDTH*(MAX_RADIX/2)-1:0] twiddle_factors_flat,
    
    // 模运算参数
    input wire [MAX_WIDTH-1:0] modulus,
    input wire [MAX_WIDTH-1:0] N_prime,
    input wire [MAX_WIDTH-1:0] R2_mod_N,  // R^2 mod N
    
    // ====================== 【修改 2】扁平输出 ======================
    output wire [MAX_WIDTH*MAX_RADIX - 1:0] data_out_flat
);

// ====================== 内部解包：扁平 → 数组（你原有逻辑不动） ======================
wire [MAX_WIDTH-1:0] data_in [0:MAX_RADIX-1];
wire [MAX_WIDTH-1:0] twiddle_factors [0:MAX_RADIX/2-1];
wire [MAX_WIDTH-1:0] data_out [0:MAX_RADIX-1];

genvar i;
generate
    // 解包输入
    for(i=0; i<MAX_RADIX; i=i+1) begin
        assign data_in[i] = data_in_flat[MAX_WIDTH*(i+1)-1 : MAX_WIDTH*i];
    end
    for(i=0; i<MAX_RADIX/2; i=i+1) begin
        assign twiddle_factors[i] = twiddle_factors_flat[MAX_WIDTH*(i+1)-1 : MAX_WIDTH*i];
    end
endgenerate

// ============================================================================
// 以下你原有代码 100% 完全不动！！！
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

wire [3:0] actual_radix = (radix_config == 2'b00) ? 4'd2 :
                         (radix_config == 2'b01) ? 4'd4 :
                         (radix_config == 2'b10) ? 4'd8 : 4'd16;

localparam [5:0] seg_count =6'd4;
localparam [7:0] seg_width = 8'd64;

// ============================================================================
// Winograd预变换模块
// ============================================================================
wire [MAX_WIDTH-1:0] winograd_x0 [0:NUM_CORES-1];
wire [MAX_WIDTH-1:0] winograd_x1 [0:NUM_CORES-1];
wire [MAX_WIDTH-1:0] winograd_w [0:NUM_CORES-1];
wire [MAX_WIDTH-1:0] winograd_conj_coeff [0:NUM_CORES-1];
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
    
    .data_in(data_in),
    .twiddle_in(twiddle_factors),
    .modulus(modulus),
    
    .x0_out(winograd_x0),
    .x1_out(winograd_x1),
    .w_out(winograd_w),
    .conj_coeff_out(winograd_conj_coeff),
    .valid_out(winograd_valid)
);

// ============================================================================
// 子核资源池
// ============================================================================
wire [MAX_WIDTH-1:0] core_result0 [0:NUM_CORES-1];
wire [MAX_WIDTH-1:0] core_result1 [0:NUM_CORES-1];
wire [NUM_CORES-1:0] core_done;
wire [NUM_CORES-1:0] core_busy;
wire [NUM_CORES-1:0] core_result_valid_array;

reg [NUM_CORES-1:0] core_enable;
always @(*) begin
    core_enable = {NUM_CORES{1'b0}};
    case(parallelism_config)
        3'b000: core_enable[0] = 1'b1;
        3'b001: core_enable[1:0] = 2'b11;
        3'b010: core_enable[3:0] = 4'b1111;
        default: core_enable = {NUM_CORES{1'b1}};
    endcase
end

genvar core_idx;
generate
    for (core_idx = 0; core_idx < NUM_CORES; core_idx = core_idx + 1) begin : core_array
        segmented_256bit_full_butterfly #(
            .TOTAL_WIDTH(128),
            .SEG_WIDTH(64),
            .SEG_COUNT(2)
        ) u_core (
            .clk(clk),
            .rst_n(rst_n),
            .start(start & core_enable[core_idx]),
            .done(core_done[core_idx]),
            .busy(core_busy[core_idx]),
            
            .x0(winograd_x0[core_idx]),
            .x1(winograd_x1[core_idx]),
            .w(winograd_w[core_idx]),
            .N_prime(N_prime),
            .modulus(modulus),
            
            .result_add(core_result0[core_idx]),
            .result_sub(core_result1[core_idx]),
            .result_valid()
        );
    end
endgenerate

// ============================================================================
// Winograd后变换
// ============================================================================
reg [MAX_WIDTH-1:0] transformed_result [0:MAX_RADIX-1];
wire post_transform_valid;

winograd_post_transform #(
    .MAX_WIDTH(MAX_WIDTH),
    .MAX_RADIX(MAX_RADIX),
    .NUM_CORES(NUM_CORES)
) u_winograd_post (
    .clk(clk),
    .rst_n(rst_n),
    
    .radix_mode(radix_config),
    
    .core_result0(core_result0),
    .core_result1(core_result1),
    .core_done(core_done),
    .conj_coeff(winograd_conj_coeff),
    .modulus(modulus),
    
    .data_out(transformed_result),
    .result_valid(post_transform_valid)
);

// ============================================================================
// 完成信号
// ============================================================================
reg all_cores_done;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        all_cores_done <= 1'b0;
    end else begin
        if (&(core_done | ~core_enable)) begin
            all_cores_done <= 1'b1;
        end else if (!start) begin
            all_cores_done <= 1'b1;
        end
    end
end

assign done = all_cores_done & post_transform_valid;
assign result_valid = done;

// ============================================================================
// 性能计数器
// ============================================================================
reg [31:0] cycle_counter;
reg [31:0] total_multiplies;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cycle_counter <= 32'd0;
        total_multiplies <= 32'd0;
    end else if (start && !done) begin
        cycle_counter <= cycle_counter + 1;
        case(radix_config)
            2'b00: total_multiplies <= total_multiplies + 1;
            2'b01: total_multiplies <= total_multiplies + 3;
            2'b10: total_multiplies <= total_multiplies + 7;
            2'b11: total_multiplies <= total_multiplies + 8;
        endcase
    end
end

// ====================== 打包输出：数组 → 扁平 ======================
generate
    for(i=0; i<MAX_RADIX; i=i+1) begin
        assign data_out_flat[MAX_WIDTH*(i+1)-1 : MAX_WIDTH*i] = transformed_result[i];
    end
endgenerate

endmodule