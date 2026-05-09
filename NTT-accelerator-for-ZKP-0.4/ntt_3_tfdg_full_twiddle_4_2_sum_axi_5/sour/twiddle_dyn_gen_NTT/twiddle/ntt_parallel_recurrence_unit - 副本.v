// ntt_parallel_recurrence_unit.v
`timescale 1ns / 1ps

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
    input wire [DATA_WIDTH-1:0] Np,        // -N^{-1} mod R (外部提供)
    input wire [DATA_WIDTH-1:0] R2_mod_N,  // R^2 mod N (外部提供)
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


reg [DATA_WIDTH-1:0] R2_mod_N_reg;
reg [DATA_WIDTH-1:0] Np_reg;

// 模乘模块实例
modular_multiplier_256bit mod_mult_inst (
    .clk(clk),
    .rst_n(reset_n),
    .start(mod_mult_start),
    .a(mod_mult_a),
    .b(mod_mult_b),
    .N(modulus),
    .Np(Np_reg),
    .R2_mod_N(R2_mod_N_reg),    
    .result(mod_mult_result),
    .done(mod_mult_done),
    .busy()
);


// ================= 状态机 =================
reg [2:0] state;
reg [3:0] counter;
reg [2:0] calc_stage;
reg [2:0] path_idx;

// 声明循环变量
integer j;  // 用于复位循环
integer m;  // 用于输出打印循环

localparam IDLE      = 3'd0;
localparam INIT      = 3'd1;
localparam CALC_POW  = 3'd2;  // 计算步进值的幂次
localparam CALC_TWID = 3'd3;  // 计算旋转因子
localparam FINISH    = 3'd4;

// 生成输出
genvar i;
generate
    for (i = 0; i < NUM_PARALLEL; i = i + 1) begin : pack_outputs
        assign twiddles_packed[i*DATA_WIDTH +: DATA_WIDTH] = current_values[i];
    end
endgenerate

// ================= 主状态机 =================
always @(posedge clk or negedge reset_n) begin
    // 复位逻辑
    if (!reset_n) begin
        state <= IDLE;
        done <= 0;
        counter <= 0;
        calc_stage <= 0;
        path_idx <= 0;
        mod_mult_start <= 0;
        
        // 复位所有寄存器
        for (j = 0; j < NUM_PARALLEL; j = j + 1) begin
            current_values[j] <= 0;
            step_powers[j] <= 0;
        end
        
        $display("[%t] NTT Parallel Unit: Reset", $time);
    end else begin
        mod_mult_start <= 0;  // 默认清零
        
        case (state)
            IDLE: begin
                if (start) begin
                    state <= INIT;
                    counter <= 0;
                    calc_stage <= 0;
                    path_idx <= 0;
                    
                    $display("[%t] NTT Parallel Unit: Starting", $time);
                    $display("[%t] NTT Parallel Unit: base_value=%h, step_value=%h", 
                             $time, base_value, step_value);
                end
            end
            
            INIT: begin
                // 初始化：第0个旋转因子是基础值本身
                current_values[0] <= base_value;
                
                // 步进值的0次幂是1
                step_powers[0] <= { {DATA_WIDTH-1{1'b0}}, 1'b1 };  // 1
                
                // 开始计算步进值的幂次
                state <= CALC_POW;
                counter <= 0;
            end
            
            CALC_POW: begin
                // 计算步进值的幂次：step_value^0, step_value^1, step_value^2, ...
                // 递推关系：step_powers[i] = step_powers[i-1] * step_value mod q
                
                if (counter == 0) begin
                    // 启动第一个乘法：step_value^1 = 1 * step_value
                    mod_mult_a <= step_powers[0];  // 1
                    mod_mult_b <= step_value;
                    mod_mult_start <= 1;
                    counter <= counter + 1;
                end else if (mod_mult_done && path_idx < NUM_PARALLEL-1) begin
                    // 乘法完成，保存结果
                    step_powers[path_idx + 1] <= mod_mult_result;
                    
                    $display("[%t] NTT Parallel Unit: step_powers[%d] = %h", 
                             $time, path_idx + 1, mod_mult_result);
                    
                    // 准备计算下一个幂次
                    if (path_idx < NUM_PARALLEL-2) begin
                        mod_mult_a <= mod_mult_result;  // 当前结果
                        mod_mult_b <= step_value;        // 乘以步进值
                        mod_mult_start <= 1;
                        path_idx <= path_idx + 1;
                    end else begin
                        // 所有幂次计算完成
                        path_idx <= 0;
                        state <= CALC_TWID;
                        counter <= 0;
                    end
                end else if (counter > 50) begin
                    // 超时保护
                    $display("[%t] NTT Parallel Unit: CALC_POW timeout", $time);
                    state <= CALC_TWID;
                    counter <= 0;
                end
            end
            
            CALC_TWID: begin
                // 计算旋转因子：base_value * step_powers[i] mod q
                // 即：ω_base^{base_exp + i*step_exp}
                
                if (counter == 0) begin
                    // 第0个已经初始化为基础值，从第1个开始计算
                    if (path_idx < NUM_PARALLEL-1) begin
                        mod_mult_a <= base_value;
                        mod_mult_b <= step_powers[path_idx + 1];
                        mod_mult_start <= 1;
                        counter <= counter + 1;
                    end else begin
                        // 所有计算完成
                        state <= FINISH;
                    end
                end else if (mod_mult_done) begin
                    // 保存计算结果
                    current_values[path_idx + 1] <= mod_mult_result;
                    
                    $display("[%t] NTT Parallel Unit: current_values[%d] = %h", 
                             $time, path_idx + 1, mod_mult_result);
                    
                    // 准备计算下一个
                    if (path_idx < NUM_PARALLEL-2) begin
                        path_idx <= path_idx + 1;
                        counter <= 0;  // 重置计数器
                    end else begin
                        // 所有计算完成
                        state <= FINISH;
                    end
                end else if (counter > 50) begin
                    // 超时保护
                    $display("[%t] NTT Parallel Unit: CALC_TWID timeout for path %d", 
                             $time, path_idx + 1);
                    if (path_idx < NUM_PARALLEL-2) begin
                        path_idx <= path_idx + 1;
                        counter <= 0;
                    end else begin
                        state <= FINISH;
                    end
                end
            end
            
            FINISH: begin
                done <= 1;
                state <= IDLE;
                
                // 打印所有结果
                $display("[%t] NTT Parallel Unit: All calculations done", $time);
                for (m = 0; m < NUM_PARALLEL; m = m + 1) begin
                    $display("  Path[%0d]: value=%h", m, current_values[m]);
                end
            end
            
            default: state <= IDLE;
        endcase
    end
end

endmodule