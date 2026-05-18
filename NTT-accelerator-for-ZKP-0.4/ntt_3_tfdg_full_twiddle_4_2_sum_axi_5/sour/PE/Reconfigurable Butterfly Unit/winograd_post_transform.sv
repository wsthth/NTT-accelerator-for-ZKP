// ============================================================================
// 文件名: winograd_post_transform.v
// 描述: Winograd后变换模块，重组子核结果为最终输出（完全可综合）
// ============================================================================
module winograd_post_transform #(
    parameter MAX_WIDTH = 384,
    parameter MAX_RADIX = 16,
    parameter NUM_CORES = 8
)(
    // 系统接口
    input wire clk,
    input wire rst_n,
    input wire start,               // 新管道调用复位

    // 配置
    input wire [1:0] radix_mode,
    input wire clear,               // 强制清零（测试用）
    
    // 子核结果输入
    input wire [MAX_WIDTH-1:0] core_result0 [0:NUM_CORES-1],
    input wire [MAX_WIDTH-1:0] core_result1 [0:NUM_CORES-1],
    input wire [NUM_CORES-1:0] core_done,
    input wire [MAX_WIDTH-1:0] conj_coeff [0:NUM_CORES-1],
    input wire [MAX_WIDTH-1:0] modulus,
    
    // 最终输出
    output reg [MAX_WIDTH-1:0] data_out [0:MAX_RADIX-1],
    output reg result_valid
);

// ============================================================================
// 内部信号和状态
// ============================================================================
reg [2:0] state;
reg [2:0] next_state;

// 基16计算的中间状态
reg [2:0] group_counter;
reg [MAX_WIDTH-1:0] temp_result;

// 独热码状态定义
localparam [2:0]
    IDLE            = 3'b001,
    WAIT_RESULTS    = 3'b010,
    RECONSTRUCT     = 3'b100;

// ============================================================================
// 模加法函数（组合逻辑，可综合）
// ============================================================================
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

// ============================================================================
// 模乘法函数（使用移位加算法，完全可综合）
// ============================================================================
function automatic [MAX_WIDTH-1:0] mod_mul;
    input [MAX_WIDTH-1:0] a;
    input [MAX_WIDTH-1:0] b;
    input [MAX_WIDTH-1:0] mod;

    reg [MAX_WIDTH-1:0] result;
    reg [MAX_WIDTH-1:0] multiplicand;
    reg [MAX_WIDTH-1:0] multiplier;
    integer i;
    begin
        result = 0;
        multiplicand = a;
        multiplier = b;

        // 使用for循环，循环次数固定，可综合
        for (i = 0; i < MAX_WIDTH; i = i + 1) begin
            // 检查multiplier的最低位
            if (multiplier[0] == 1'b1) begin
                // 调用mod_add函数（组合逻辑）
                result = mod_add(result, multiplicand, mod);
            end

            // multiplicand乘以2（模意义下）
            multiplicand = mod_add(multiplicand, multiplicand, mod);

            // multiplier右移1位
            multiplier = multiplier >> 1;
        end

        mod_mul = result;
    end
endfunction









// ============================================================================
// 方法1：将core_done转换为电平信号
// ============================================================================
reg [NUM_CORES-1:0] core_done_latched;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        core_done_latched <= {NUM_CORES{1'b0}};
    end else if (clear || start) begin
        // 清零
        core_done_latched <= {NUM_CORES{1'b0}};
    end else begin
        // 粘性锁存：core_done 脉冲到来时置 1，只在 start 时清零
        for (integer i = 0; i < NUM_CORES; i = i + 1) begin
            if (core_done[i]) begin
                core_done_latched[i] <= 1'b1;
            end
        end
    end
end

// 使用锁存后的信号
wire [NUM_CORES-1:0] post_transform_core_done = core_done_latched;

// ============================================================================
// 状态机主逻辑
// ============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
        result_valid <= 1'b0;
        group_counter <= 0;
        temp_result <= 0;
        for (integer i = 0; i < MAX_RADIX; i = i + 1) begin
            data_out[i] <= {MAX_WIDTH{1'b0}};
        end
    end else if (start || clear) begin
        // 新管道调用或清零：复位状态机
        state <= IDLE;
        result_valid <= 1'b0;
        group_counter <= 0;
        temp_result <= 0;
    end else begin
        state <= next_state;
        
        case(state)
            IDLE: begin
                result_valid <= 1'b0;
                group_counter <= 0;
                // if (|core_done) begin
                if (|post_transform_core_done) begin
                    next_state <= WAIT_RESULTS;
                end else begin
                    next_state <= IDLE;
                end
            end
            
            WAIT_RESULTS: begin
                // 检查所有需要的子核是否完成
                case(radix_mode)
                    2'b00: begin  // 基2：等待子核0
                        // if (core_done[0]) begin
                        if (post_transform_core_done[0]) begin
                            next_state <= RECONSTRUCT;
                        end else begin
                            next_state <= WAIT_RESULTS;
                        end
                    end
                    2'b01: begin  // 基4：等待子核0,1
                        // if (core_done[1:0] == 2'b11) begin
                        if (post_transform_core_done[1:0] == 2'b11) begin
                            next_state <= RECONSTRUCT;
                        end else begin
                            next_state <= WAIT_RESULTS;
                        end
                    end
                    2'b10: begin  // 基8：等待子核0-3
                        // if (core_done[3:0] == 4'b1111) begin
                        if (post_transform_core_done[3:0] == 4'b1111) begin
                            next_state <= RECONSTRUCT;
                        end else begin
                            next_state <= WAIT_RESULTS;
                        end
                    end
                    2'b11: begin  // 基16：等待所有8个子核
                        // if (core_done == {NUM_CORES{1'b1}}) begin
                        if (post_transform_core_done == {NUM_CORES{1'b1}}) begin
                            next_state <= RECONSTRUCT;
                        end else begin
                            next_state <= WAIT_RESULTS;
                        end
                    end
                    default: begin
                        next_state <= IDLE;
                    end
                endcase
            end
            
            RECONSTRUCT: begin
                case(radix_mode)
                    2'b00: begin  // 基2
                        data_out[0] <= core_result0[0];
                        data_out[1] <= core_result1[0];
                        result_valid <= 1'b1;
                        next_state <= IDLE;
                    end
                    
                    2'b01: begin  // 基4
                        data_out[0] <= core_result0[0];
                        data_out[1] <= core_result1[0];
                        data_out[2] <= core_result0[1];
                        data_out[3] <= core_result1[1];
                        result_valid <= 1'b1;
                        next_state <= IDLE;
                    end
                    
                    2'b10: begin  // 基8
                        for (integer i = 0; i < 4; i = i + 1) begin
                            data_out[i*2] <= core_result0[i];
                            data_out[i*2+1] <= core_result1[i];
                        end
                        result_valid <= 1'b1;
                        next_state <= IDLE;
                    end
                    
                    2'b11: begin  // 基16
                        // 分步处理8个组，避免长组合逻辑路径
                        if (group_counter < 8) begin
                            // 当前组的结果直接存储
                            data_out[group_counter] <= core_result0[group_counter];
                            
                            // 计算对称位置的模乘法结果
                            temp_result <= mod_mul(
                                core_result1[group_counter],
                                conj_coeff[group_counter],
                                modulus
                            );
                            
                            group_counter <= group_counter + 1;
                            next_state <= RECONSTRUCT;
                        end else begin
                            // 所有组处理完成
                            result_valid <= 1'b1;
                            next_state <= IDLE;
                        end
                    end
                    
                    default: begin
                        result_valid <= 1'b0;
                        next_state <= IDLE;
                    end
                endcase
                
                // 在基16中，对称位置的结果延迟一个周期存储
                if (radix_mode == 2'b11 && group_counter > 0) begin
                    data_out[15 - (group_counter - 1)] <= temp_result;
                end
            end
            
            default: begin
                next_state <= IDLE;
                result_valid <= 1'b0;
            end
        endcase
    end
end

endmodule