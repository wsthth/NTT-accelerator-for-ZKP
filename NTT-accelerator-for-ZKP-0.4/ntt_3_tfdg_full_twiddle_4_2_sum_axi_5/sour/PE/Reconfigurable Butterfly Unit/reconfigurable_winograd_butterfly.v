// ============================================================================
// File Name: reconfigurable_winograd_butterfly.v
// Description: Unified butterfly engine - true hardware sharing
// ============================================================================
module reconfigurable_winograd_butterfly #(
    parameter DATA_WIDTH = 128,
    parameter MAX_RADIX = 4,
    parameter MULT_ARRAY_SIZE = 4,  // Multiplier array size
    parameter PIPELINE_STAGES = 4,  // Multiplier pipeline depth
    parameter EXP_WIDTH = 8         // Exponent width
)(
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [3:0] radix_cfg,      // Radix configuration: 2/4/8/16 (must be power of 2)
    input wire [1:0] width_cfg,      // Width configuration
    
    // Input data ports - flattened arrays
    input wire [DATA_WIDTH*MAX_RADIX-1:0] x_in_flat,
    input wire [DATA_WIDTH-1:0] twiddle_base,     // Base twiddle factor ω
    input wire [DATA_WIDTH-1:0] modulus,
    input wire [DATA_WIDTH-1:0] N_prime,
    input wire [DATA_WIDTH-1:0] R2_mod_N,  // R^2 mod N (for modular exponentiation)
    
    // Output data ports - flattened arrays
    output reg [DATA_WIDTH*MAX_RADIX-1:0] x_out_flat,
    output reg done,
    output reg valid
);

// ============================================================================
// Internal signal definitions
// ============================================================================
reg [DATA_WIDTH-1:0] multiplier_array [0:MULT_ARRAY_SIZE-1];
reg [DATA_WIDTH-1:0] multiplicand_array [0:MULT_ARRAY_SIZE-1];
wire [DATA_WIDTH-1:0] product_array [0:MULT_ARRAY_SIZE-1];
reg [MULT_ARRAY_SIZE-1:0] mult_start;
wire [MULT_ARRAY_SIZE-1:0] mult_done;
wire [MULT_ARRAY_SIZE-1:0] mult_valid;

// Modular exponentiation signals
wire [DATA_WIDTH-1:0] twiddle_power_result;
wire twiddle_power_done;
reg twiddle_power_start;
reg [DATA_WIDTH-1:0] twiddle_power_base;
reg [EXP_WIDTH-1:0] twiddle_power_exp;

// Accumulator
reg [DATA_WIDTH-1:0] accumulator [0:MAX_RADIX-1];
reg [3:0] accum_idx [0:MULT_ARRAY_SIZE-1];

// State machine
reg [3:0] state;
reg [3:0] next_state;
reg [3:0] j_counter;      // Input index counter
reg [3:0] k_counter;      // Output index counter
reg [7:0] cycle_counter;

// WNTT coefficients
reg [DATA_WIDTH-1:0] wntt_coeff [0:MAX_RADIX-1][0:MAX_RADIX-1];
reg coeff_ready;

// Unflattened input/output arrays
reg [DATA_WIDTH-1:0] x_in [0:MAX_RADIX-1];
reg [DATA_WIDTH-1:0] x_out [0:MAX_RADIX-1];

// Mask calculation: for power of 2 N, modulo N equals & (N-1)
wire [3:0] radix_mask = radix_cfg - 1'b1;

// State definitions
localparam [3:0]
    STATE_IDLE        = 4'd0,
    STATE_INIT        = 4'd1,
    STATE_CALC_COEFF  = 4'd2,  // Calculate coefficients state
    STATE_LOAD        = 4'd3,
    STATE_MULT        = 4'd4,
    STATE_ACCUM       = 4'd5,
    STATE_WAIT        = 4'd6,
    STATE_OUTPUT      = 4'd7;

// ============================================================================
// Integer variables for loops (declared at module level)
// ============================================================================
integer accum_i;               // For accumulator index configuration
integer init_i, init_j;        // For initialization loops
integer load_k_idx;            // For STATE_LOAD loop
integer accum_loop_idx;        // For STATE_ACCUM loop
integer output_loop_idx;       // For STATE_OUTPUT loop

// ============================================================================
// 初始化整数变量
// ============================================================================
initial begin
    accum_i = 0;
    init_i = 0;
    init_j = 0;
    load_k_idx = 0;
    accum_loop_idx = 0;
    output_loop_idx = 0;
end

// ============================================================================
// Flatten/Unflatten input and output arrays
// ============================================================================
genvar unflatten_idx;
generate
    // Unflatten input array
    for (unflatten_idx = 0; unflatten_idx < MAX_RADIX; unflatten_idx = unflatten_idx + 1) begin : unflatten_input
        always @(*) begin
            x_in[unflatten_idx] = x_in_flat[unflatten_idx*DATA_WIDTH +: DATA_WIDTH];
        end
    end
    
    // Flatten output array
    for (unflatten_idx = 0; unflatten_idx < MAX_RADIX; unflatten_idx = unflatten_idx + 1) begin : flatten_output
        always @(*) begin
            x_out_flat[unflatten_idx*DATA_WIDTH +: DATA_WIDTH] = x_out[unflatten_idx];
        end
    end
endgenerate

// ============================================================================
// Modular exponentiation module instantiation
// ============================================================================
modular_exponentiation #(
    .DATA_WIDTH(DATA_WIDTH),
    .EXP_WIDTH(EXP_WIDTH)
) u_mod_exp (
    .clk(clk),
    .reset_n(rst_n),
    .start(twiddle_power_start),
    .base(twiddle_power_base),
    .exponent(twiddle_power_exp),
    .modulus(modulus),
    .Np(N_prime),
    .R2_mod_N(R2_mod_N),
    .result(twiddle_power_result),
    .done(twiddle_power_done)
);

// ============================================================================
// Segmented multiplier array instantiation
// ============================================================================
genvar mult_idx;
generate
    for (mult_idx = 0; mult_idx < MULT_ARRAY_SIZE; mult_idx = mult_idx + 1) begin : mult_array
        segmented_256bit_butterfly #(
            .TOTAL_WIDTH(DATA_WIDTH),
            .SEG_WIDTH(64),
            .SEG_COUNT(DATA_WIDTH/64)
        ) u_multiplier (
            .clk(clk),
            .rst_n(rst_n),
            .start(mult_start[mult_idx]),
            .add_mode(1'b0),
            .done(mult_done[mult_idx]),
            .busy(),
            .x0(multiplicand_array[mult_idx]),
            .x1(multiplier_array[mult_idx]),
            .w(multiplier_array[mult_idx]),
            .N_prime(N_prime),
            .modulus(modulus),
            .result(product_array[mult_idx]),
            .result_valid(mult_valid[mult_idx])
        );
    end
endgenerate

// ============================================================================
// Helper function: calculate j * k mod radix (using bitwise optimization)
// ============================================================================
function [EXP_WIDTH-1:0] mod_radix_mult;
    input [3:0] j;
    input [3:0] k;
    input [3:0] radix;
    reg [7:0] product;
    begin
        product = j * k;
        // For power of 2, modulo is equivalent to AND with mask
        case (radix)
            4'd2:  mod_radix_mult = product[0];        // Take LSB
            4'd4:  mod_radix_mult = product[1:0];      // Take lower 2 bits
            4'd8:  mod_radix_mult = product[2:0];      // Take lower 3 bits
            default: mod_radix_mult = product[3:0];    // Take lower 4 bits (for radix 16)
        endcase
    end
endfunction

// ============================================================================
// Dynamic accumulator index configuration
// ============================================================================
always @(*) begin
    for (accum_i = 0; accum_i < MULT_ARRAY_SIZE; accum_i = accum_i + 1) begin
        case (radix_cfg)
            4'd2: begin
                if (accum_i < 2) begin
                    accum_idx[accum_i] = (accum_i == 0) ? 4'h0 : 4'h1;
                end else begin
                    accum_idx[accum_i] = 4'hF;
                end
            end
            4'd4: begin
                if (accum_i < 16) begin
                    accum_idx[accum_i] = accum_i & 2'b11;  // Changed to bitwise: i % 4 equals i & 3
                end else begin
                    accum_idx[accum_i] = 4'hF;
                end
            end
            default: begin
                accum_idx[accum_i] = 4'hF;
            end
        endcase
    end
end

// ============================================================================
// 用于跟踪模幂计算状态的寄存器
// ============================================================================
reg mod_exp_processing;

// ============================================================================
// 状态机组合逻辑部分
// ============================================================================
always @(*) begin
    next_state = state;  // 默认保持当前状态
    
    case (state)
        STATE_IDLE: begin
            if (start) begin
                next_state = STATE_INIT;
            end else begin
                next_state = STATE_IDLE;
            end
        end
        
        STATE_INIT: begin
            next_state = STATE_CALC_COEFF;
        end
        
        STATE_CALC_COEFF: begin
            if (coeff_ready) begin
                next_state = STATE_LOAD;
            end else begin
                next_state = STATE_CALC_COEFF;
            end
        end
        
        STATE_LOAD: begin
            case (radix_cfg)
                4'd2: begin
                    if (j_counter < 2) begin
                        next_state = STATE_MULT;
                    end else begin
                        next_state = STATE_WAIT;
                    end
                end
                4'd4: begin
                    if (j_counter < 4) begin
                        next_state = STATE_MULT;
                    end else begin
                        next_state = STATE_WAIT;
                    end
                end
                default: begin
                    next_state = STATE_IDLE;
                end
            endcase
        end
        
        STATE_MULT: begin
            // 等待所有启动的乘法器完成
            if (mult_done == {MULT_ARRAY_SIZE{1'b1}}) begin
                next_state = STATE_ACCUM;
            end else if (cycle_counter > 8'd50) begin // 超时保护
                next_state = STATE_ACCUM;
            end else begin
                next_state = STATE_MULT;
            end
        end
        
        STATE_ACCUM: begin
            next_state = STATE_LOAD;
        end
        
        STATE_WAIT: begin
            if (cycle_counter > 8'd10) begin
                next_state = STATE_OUTPUT;
            end else begin
                next_state = STATE_WAIT;
            end
        end
        
        STATE_OUTPUT: begin
            next_state = STATE_IDLE;
        end
        
        default: begin
            next_state = STATE_IDLE;
        end
    endcase
end

// ============================================================================
// 状态机时序逻辑部分
// ============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= STATE_IDLE;
        done <= 1'b0;
        valid <= 1'b0;
        j_counter <= 4'b0;
        k_counter <= 4'b0;
        cycle_counter <= 8'b0;
        coeff_ready <= 1'b0;
        twiddle_power_start <= 1'b0;
        twiddle_power_base <= {DATA_WIDTH{1'b0}};
        twiddle_power_exp <= {EXP_WIDTH{1'b0}};
        mod_exp_processing <= 1'b0;
        
        // 初始化所有阵列
        for (init_i = 0; init_i < MAX_RADIX; init_i = init_i + 1) begin
            accumulator[init_i] <= {DATA_WIDTH{1'b0}};
            x_out[init_i] <= {DATA_WIDTH{1'b0}};
        end
        
        for (init_i = 0; init_i < MULT_ARRAY_SIZE; init_i = init_i + 1) begin
            multiplier_array[init_i] <= {DATA_WIDTH{1'b0}};
            multiplicand_array[init_i] <= {DATA_WIDTH{1'b0}};
        end
        
        // 初始化WNTT系数矩阵
        for (init_i = 0; init_i < MAX_RADIX; init_i = init_i + 1) begin
            for (init_j = 0; init_j < MAX_RADIX; init_j = init_j + 1) begin
                wntt_coeff[init_i][init_j] <= {DATA_WIDTH{1'b0}};
            end
        end
        
        mult_start <= {MULT_ARRAY_SIZE{1'b0}};
        
        // 初始化整数变量
        accum_i = 0;
        init_i = 0;
        init_j = 0;
        load_k_idx = 0;
        accum_loop_idx = 0;
        output_loop_idx = 0;
    end else begin
        state <= next_state;
        
        // cycle_counter在非空闲状态下递增
        if (state != STATE_IDLE && next_state != STATE_IDLE) begin
            cycle_counter <= cycle_counter + 8'b1;
        end else begin
            cycle_counter <= 8'b0;
        end
        
        case (state)
            STATE_IDLE: begin
                done <= 1'b0;
                valid <= 1'b0;
                if (start) begin
                    j_counter <= 4'b0;
                    k_counter <= 4'b0;
                    coeff_ready <= 1'b0;
                    mod_exp_processing <= 1'b0;
                end
            end
            
            STATE_INIT: begin
                // 重置累加器
                for (init_i = 0; init_i < MAX_RADIX; init_i = init_i + 1) begin
                    accumulator[init_i] <= {DATA_WIDTH{1'b0}};
                end
                    
                // 重置计数器
                j_counter <= 4'b0;
                k_counter <= 4'b0;
                cycle_counter <= 8'b0;
                coeff_ready <= 1'b0;
            end
            
            STATE_CALC_COEFF: begin
                // 计算WNTT系数矩阵
                if (!coeff_ready) begin
                    if (j_counter < MAX_RADIX && k_counter < MAX_RADIX) begin
                        if (!mod_exp_processing && !twiddle_power_done) begin
                            // 启动模幂运算计算 ω^((j*k) mod radix_cfg)
                            twiddle_power_base <= twiddle_base;
                            twiddle_power_exp <= mod_radix_mult(j_counter, k_counter, radix_cfg);
                            twiddle_power_start <= 1'b1;
                            mod_exp_processing <= 1'b1;
                        end else if (twiddle_power_start) begin
                            // 启动信号只持续一个周期
                            twiddle_power_start <= 1'b0;
                        end else if (twiddle_power_done && mod_exp_processing) begin
                            // 模幂运算完成，存储结果
                            wntt_coeff[k_counter][j_counter] <= twiddle_power_result;
                            mod_exp_processing <= 1'b0;
                            
                            // 更新索引
                            if (j_counter < MAX_RADIX - 1) begin
                                j_counter <= j_counter + 4'b1;
                            end else begin
                                j_counter <= 4'b0;
                                if (k_counter < MAX_RADIX - 1) begin
                                    k_counter <= k_counter + 4'b1;
                                end else begin
                                    k_counter <= 4'b0;
                                    coeff_ready <= 1'b1;
                                end
                            end
                        end
                    end
                end
            end
            
            STATE_LOAD: begin
                case (radix_cfg)
                    4'd2: begin
                        if (j_counter < 2) begin
                            multiplier_array[0] <= x_in[0];
                            multiplicand_array[0] <= wntt_coeff[0][j_counter];
                            multiplier_array[1] <= x_in[1];
                            multiplicand_array[1] <= wntt_coeff[1][j_counter];
                            mult_start <= 2'b11;
                            j_counter <= j_counter + 4'b1;
                        end else begin
                            mult_start <= 2'b00;
                            j_counter <= 4'b0;
                        end
                    end
                    
                    4'd4: begin
                        if (j_counter < 4) begin
                            // 重置循环变量
                            load_k_idx = 0;
                            for (load_k_idx = 0; load_k_idx < 4; load_k_idx = load_k_idx + 1) begin
                                if (load_k_idx < MULT_ARRAY_SIZE) begin
                                    multiplier_array[load_k_idx] <= x_in[j_counter];
                                    multiplicand_array[load_k_idx] <= wntt_coeff[load_k_idx][j_counter];
                                end
                            end
                            mult_start <= 4'b1111;
                            j_counter <= j_counter + 4'b1;
                        end else begin
                            mult_start <= 4'b0000;
                            j_counter <= 4'b0;
                        end
                    end
                endcase
            end
            
            STATE_MULT: begin
                // 乘法器启动后立即清零，只持续一个周期
                if (mult_start != {MULT_ARRAY_SIZE{1'b0}}) begin
                    mult_start <= {MULT_ARRAY_SIZE{1'b0}};
                end
            end
            
            STATE_ACCUM: begin
                // 重置循环变量
                accum_loop_idx = 0;
                
                // 累加乘法器结果
                for (accum_loop_idx = 0; accum_loop_idx < MULT_ARRAY_SIZE; accum_loop_idx = accum_loop_idx + 1) begin
                    if (mult_valid[accum_loop_idx] && accum_idx[accum_loop_idx] != 4'hF) begin
                        accumulator[accum_idx[accum_loop_idx]] <= accumulator[accum_idx[accum_loop_idx]] + product_array[accum_loop_idx];
                    end
                end
                cycle_counter <= 8'b0;  // 重置延时计数器
            end
            
            STATE_WAIT: begin
                // 等待累积完成
                if (cycle_counter > 8'd10) begin
                    cycle_counter <= 8'b0;
                end
            end
            
            STATE_OUTPUT: begin
                case (radix_cfg)
                    4'd2: begin
                        x_out[0] <= accumulator[0];
                        x_out[1] <= accumulator[1];
                    end
                    4'd4: begin
                        // 重置循环变量
                        output_loop_idx = 0;
                        for (output_loop_idx = 0; output_loop_idx < 4; output_loop_idx = output_loop_idx + 1) begin
                            x_out[output_loop_idx] <= accumulator[output_loop_idx];
                        end
                    end
                endcase
                
                valid <= 1'b1;
                done <= 1'b1;
            end
        endcase
    end
end

// ============================================================================
// Performance monitoring
// ============================================================================
reg [15:0] total_cycles;
always @(posedge clk) begin
    if (state == STATE_IDLE) begin
        total_cycles <= 16'b0;
    end else if (state != STATE_IDLE && next_state != STATE_IDLE) begin
        total_cycles <= total_cycles + 16'b1;
    end
end

// Debug signals
wire [3:0] debug_state = state;
wire [15:0] debug_cycles = total_cycles;

// 添加调试输出
reg [DATA_WIDTH-1:0] debug_coeff_00;
reg [DATA_WIDTH-1:0] debug_coeff_01;
reg [DATA_WIDTH-1:0] debug_acc_0;
reg [DATA_WIDTH-1:0] debug_acc_1;

always @(posedge clk) begin
    debug_coeff_00 <= wntt_coeff[0][0];
    debug_coeff_01 <= wntt_coeff[0][1];
    debug_acc_0 <= accumulator[0];
    debug_acc_1 <= accumulator[1];
end


// ============================================================================
// 添加详细的调试模块
// ============================================================================

// 调试：监控乘法器状态
reg [7:0] debug_mult_state [0:MULT_ARRAY_SIZE-1];
reg [DATA_WIDTH-1:0] debug_product_values [0:MULT_ARRAY_SIZE-1];
reg [MULT_ARRAY_SIZE-1:0] debug_mult_valid_history;

always @(posedge clk) begin
    for (integer i = 0; i < MULT_ARRAY_SIZE; i = i + 1) begin
        debug_mult_state[i] <= {mult_start[i], mult_done[i], mult_valid[i]};
        debug_product_values[i] <= product_array[i];
    end
    debug_mult_valid_history <= mult_valid;
end

// 调试：在关键状态添加显示信息
always @(posedge clk) begin
    if (state == STATE_ACCUM) begin
        $display("========================================");
        $display("[%t] STATE_ACCUM: Checking multiplier outputs", $time);
        $display("  mult_valid = %b", mult_valid);
        $display("  accum_idx = [%h, %h, %h, %h]", 
                 accum_idx[0], accum_idx[1], accum_idx[2], accum_idx[3]);
        
        for (integer i = 0; i < MULT_ARRAY_SIZE; i = i + 1) begin
            if (mult_valid[i] && accum_idx[i] != 4'hF) begin
                $display("  Multiplier %d: product=%h, accum_idx=%h, will add to accumulator[%h]",
                         i, product_array[i], accum_idx[i], accum_idx[i]);
            end else begin
                $display("  Multiplier %d: mult_valid=%b, accum_idx=%h (skipped)",
                         i, mult_valid[i], accum_idx[i]);
            end
        end
        
        $display("  Current accumulators:");
        for (integer i = 0; i < MAX_RADIX; i = i + 1) begin
            $display("    accumulator[%d] = %h", i, accumulator[i]);
        end
    end
    
    if (state == STATE_LOAD) begin
        $display("[%t] STATE_LOAD: j_counter=%d", $time, j_counter);
        $display("  Loading data to multipliers:");
        for (integer i = 0; i < MULT_ARRAY_SIZE; i = i + 1) begin
            $display("    Multiplier %d: x=%h, coeff=%h", 
                     i, multiplier_array[i], multiplicand_array[i]);
        end
    end
end

// 调试：监控系数矩阵
reg [DATA_WIDTH-1:0] debug_wntt_coeff_monitor [0:3];
always @(posedge clk) begin
    if (coeff_ready) begin
        debug_wntt_coeff_monitor[0] <= wntt_coeff[0][0];
        debug_wntt_coeff_monitor[1] <= wntt_coeff[0][1];
        debug_wntt_coeff_monitor[2] <= wntt_coeff[1][0];
        debug_wntt_coeff_monitor[3] <= wntt_coeff[1][1];
    end
end

// 调试：监控模幂运算
always @(posedge clk) begin
    if (state == STATE_CALC_COEFF) begin
        if (twiddle_power_start) begin
            $display("[%t] STATE_CALC_COEFF: Starting modular exponentiation", $time);
            $display("  base=%h, exp=%h, j_counter=%d, k_counter=%d", 
                     twiddle_power_base, twiddle_power_exp, j_counter, k_counter);
        end
        
        if (twiddle_power_done) begin
            $display("[%t] STATE_CALC_COEFF: Modular exponentiation done", $time);
            $display("  result=%h, storing to wntt_coeff[%d][%d]", 
                     twiddle_power_result, k_counter, j_counter);
        end
    end
end




endmodule