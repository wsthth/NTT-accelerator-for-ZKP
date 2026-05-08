// ntt_parallel_recurrence_unit.v 修复版本

module ntt_parallel_recurrence_unit #(
    parameter NUM_PARALLEL = 4,
    parameter DATA_WIDTH = 256
)(
    input wire clk,
    input wire reset_n,
    input wire start,
    input wire [DATA_WIDTH-1:0] base_value,
    input wire [DATA_WIDTH-1:0] step_value,
    input wire [DATA_WIDTH-1:0] modulus,
    input wire [DATA_WIDTH-1:0] Np,        // -N^{-1} mod R
    input wire [DATA_WIDTH-1:0] R2_mod_N,  // R^2 mod N
    output wire [DATA_WIDTH*NUM_PARALLEL-1:0] twiddles_packed,
    output reg done
);

// ================= 内部寄存器 =================
reg [DATA_WIDTH-1:0] current_values [0:NUM_PARALLEL-1];
reg [DATA_WIDTH-1:0] step_powers [0:NUM_PARALLEL-1];

// 模乘接口
wire [DATA_WIDTH-1:0] mod_mult_result;
wire mod_mult_done;
reg mod_mult_start;
reg [DATA_WIDTH-1:0] mod_mult_a;
reg [DATA_WIDTH-1:0] mod_mult_b;

// 状态机
reg [2:0] state;
reg [3:0] counter;
reg [2:0] path_idx;

// 锁存输入
reg [DATA_WIDTH-1:0] base_value_reg;
reg [DATA_WIDTH-1:0] step_value_reg;
reg [DATA_WIDTH-1:0] modulus_reg;
reg [DATA_WIDTH-1:0] Np_reg;
reg [DATA_WIDTH-1:0] R2_mod_N_reg;

localparam IDLE      = 3'd0;
localparam INIT      = 3'd1;
localparam CALC_POW  = 3'd2;
localparam CALC_TWID = 3'd3;
localparam FINISH    = 3'd4;

// 生成输出
genvar i;
generate
    for (i = 0; i < NUM_PARALLEL; i = i + 1) begin : pack_outputs
        assign twiddles_packed[i*DATA_WIDTH +: DATA_WIDTH] = current_values[i];
    end
endgenerate

// 模乘模块实例
modular_multiplier_256bit mod_mult_inst (
    .clk(clk),
    .rst_n(reset_n),
    .start(mod_mult_start),
    .a(mod_mult_a),
    .b(mod_mult_b),
    .N(modulus_reg),     // 使用锁存的模数
    .Np(Np_reg),         // 使用锁存的Np
    .R2_mod_N(R2_mod_N_reg), // 使用锁存的R2_mod_N
    .result(mod_mult_result),
    .done(mod_mult_done),
    .busy()
);

// ================= 主状态机 =================
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        state <= IDLE;
        done <= 0;
        counter <= 0;
        path_idx <= 0;
        mod_mult_start <= 0;
        
        // 初始化数组
        for (integer j = 0; j < NUM_PARALLEL; j = j + 1) begin
            current_values[j] <= 0;
            step_powers[j] <= 0;
        end
        
        // 复位锁存寄存器
        base_value_reg <= 0;
        step_value_reg <= 0;
        modulus_reg <= 0;
        Np_reg <= 0;
        R2_mod_N_reg <= 0;
        
        $display("[%t] NTT Parallel Unit: Reset", $time);
    end else begin
        // 默认值
        mod_mult_start <= 0;
        
        case (state)
            IDLE: begin
                if (start) begin
                    // 锁存所有输入
                    base_value_reg <= base_value;
                    step_value_reg <= step_value;
                    modulus_reg <= modulus;
                    Np_reg <= Np;
                    R2_mod_N_reg <= R2_mod_N;
                    
                    state <= INIT;
                    counter <= 0;
                    path_idx <= 0;
                    done <= 0;
                    
                    $display("[%t] NTT Parallel Unit: Starting calculation", $time);
                    $display("[%t] base=%h, step=%h, mod=%h", 
                             $time, base_value, step_value, modulus);
                end
            end
            
            INIT: begin
                // 初始化：第0个旋转因子是基础值本身
                // 注意：base_value已经是普通域，直接使用
                current_values[0] <= base_value_reg;
                
                // 步进值的0次幂是1（普通域）
                step_powers[0] <= { {DATA_WIDTH-1{1'b0}}, 1'b1 };  // 1
                
                // 直接开始计算步进值的幂次
                state <= CALC_POW;
                counter <= 0;
                path_idx <= 0;
                
                $display("[%t] NTT Parallel Unit: INIT complete", $time);
            end
            
            CALC_POW: begin
                // 计算步进值的幂次：step_value^i mod modulus
                // 使用普通域的模乘，递推关系：step_powers[i] = step_powers[i-1] * step_value mod modulus
                
                if (counter == 0 && path_idx == 0) begin
                    // 计算 step_value^1
                    mod_mult_a <= step_powers[0];  // 1
                    mod_mult_b <= step_value_reg;   // step_value
                    mod_mult_start <= 1;
                    counter <= 1;
                    
                    $display("[%t] NTT Parallel Unit: Starting step^1 calculation", $time);
                end else if (mod_mult_done) begin
                    // 保存结果
                    step_powers[path_idx + 1] <= mod_mult_result;
                    
                    $display("[%t] NTT Parallel Unit: step_powers[%d] = %h", 
                             $time, path_idx + 1, mod_mult_result);
                    
                    // 准备计算下一个幂次
                    if (path_idx < NUM_PARALLEL - 2) begin
                        // 计算下一个幂次：step_powers[path_idx+1] * step_value
                        mod_mult_a <= mod_mult_result;  // 刚刚计算的结果
                        mod_mult_b <= step_value_reg;    // step_value
                        mod_mult_start <= 1;
                        path_idx <= path_idx + 1;
                        counter <= 1;  // 重置计数器
                        
                        $display("[%t] NTT Parallel Unit: Starting step^%d calculation", 
                                 $time, path_idx + 2);
                    end else begin
                        // 所有幂次计算完成
                        path_idx <= 0;
                        state <= CALC_TWID;
                        counter <= 0;
                        
                        $display("[%t] NTT Parallel Unit: All step powers calculated", $time);
                    end
                end else if (counter > 100) begin
                    // 超时保护
                    $display("[%t] NTT Parallel Unit: CALC_POW timeout at path_idx=%d", 
                             $time, path_idx);
                    state <= CALC_TWID;
                    counter <= 0;
                end else begin
                    counter <= counter + 1;
                end
            end
            
            CALC_TWID: begin
                // 计算旋转因子：base_value * step_powers[i] mod modulus
                // 即：base_value * step_value^i mod modulus
                
                if (counter == 0) begin
                    // 从i=1开始计算（i=0已经在INIT中设置为基础值）
                    if (path_idx < NUM_PARALLEL - 1) begin
                        mod_mult_a <= base_value_reg;           // 基础值
                        mod_mult_b <= step_powers[path_idx + 1]; // step_value^i
                        mod_mult_start <= 1;
                        counter <= 1;
                        
                        $display("[%t] NTT Parallel Unit: Starting twiddle[%d] calculation", 
                                 $time, path_idx + 1);
                    end else begin
                        // 所有计算完成
                        state <= FINISH;
                        $display("[%t] NTT Parallel Unit: All twiddles calculated", $time);
                    end
                end else if (mod_mult_done) begin
                    // 保存计算结果
                    current_values[path_idx + 1] <= mod_mult_result;
                    
                    $display("[%t] NTT Parallel Unit: current_values[%d] = %h", 
                             $time, path_idx + 1, mod_mult_result);
                    
                    // 准备计算下一个
                    if (path_idx < NUM_PARALLEL - 2) begin
                        path_idx <= path_idx + 1;
                        counter <= 0;
                    end else begin
                        // 所有计算完成
                        state <= FINISH;
                    end
                end else if (counter > 100) begin
                    // 超时保护
                    $display("[%t] NTT Parallel Unit: CALC_TWID timeout at path_idx=%d", 
                             $time, path_idx);
                    if (path_idx < NUM_PARALLEL - 2) begin
                        path_idx <= path_idx + 1;
                        counter <= 0;
                    end else begin
                        state <= FINISH;
                    end
                end else begin
                    counter <= counter + 1;
                end
            end
            
            FINISH: begin
                done <= 1;
                state <= IDLE;
                
                // 打印所有结果
                $display("[%t] NTT Parallel Unit: All calculations done", $time);
                for (integer m = 0; m < NUM_PARALLEL; m = m + 1) begin
                    $display("  Path[%0d]: value=%h", m, current_values[m]);
                end
            end
            
            default: state <= IDLE;
        endcase
    end
end

endmodule