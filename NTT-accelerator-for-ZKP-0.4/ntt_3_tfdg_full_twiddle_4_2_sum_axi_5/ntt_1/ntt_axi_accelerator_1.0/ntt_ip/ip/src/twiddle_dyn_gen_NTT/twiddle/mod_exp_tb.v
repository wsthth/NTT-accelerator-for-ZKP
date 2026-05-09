// mod_exp_tb.v
`timescale 1ns / 1ps

module mod_exp_tb;

// ================= 参数定义 =================
parameter DATA_WIDTH = 256;
parameter EXP_WIDTH = 256;

// ================= 信号定义 =================
reg clk;
reg reset_n;
reg start;
wire done;

reg [DATA_WIDTH-1:0] base;
reg [EXP_WIDTH-1:0] exponent;
reg [DATA_WIDTH-1:0] modulus;
reg [DATA_WIDTH-1:0] Np;
reg [DATA_WIDTH-1:0] R2_mod_N;

wire [DATA_WIDTH-1:0] result;
// wire [DATA_WIDTH:0] result;
// ================= 时钟生成 =================
initial begin
    clk = 0;
    forever #5 clk = ~clk;  // 100MHz时钟
end

// ================= 顶层模块实例化 =================
modular_exponentiation #(
    .DATA_WIDTH(DATA_WIDTH),
    .EXP_WIDTH(EXP_WIDTH)
) dut (
    .clk(clk),
    .reset_n(reset_n),
    .start(start),
    .done(done),
    .base(base),
    .exponent(exponent),
    .modulus(modulus),
    .Np(Np),
    .R2_mod_N(R2_mod_N),
    .result(result)
);

// ================= 测试序列 =================
initial begin
    // 初始化
    reset_n = 0;
    start = 0;
    base = 0;
    exponent = 0;
    modulus = 0;
    Np = 0;
    R2_mod_N = 0;
    
    // 复位
    #20 reset_n = 1;
    
    // 等待一段时间
    #10;
    
    // 测试用例1：简单测试
    $display("[%t] Test 1: Simple modular exponentiation", $time);
/*     base = 256'd123456789;                    // base = 3
    exponent = 256'd12345;              // exponent = 4
    modulus = 256'd1000000007;               // modulus = 7 (odd prime)
 */    
    
    // 注意：在实际使用中，Np和R2_mod_N需要正确计算
    // 这里仅作为示例，使用简单的值
/*     Np = 256'd14412540391571238400966997766934456954787576109662604465421775855956845362249;                    // 简化的Np
    R2_mod_N = 256'd418385479;              // 简化的R2_mod_N
 */

/*     base = 256'd123456789;                    // base = 3
    exponent = 256'd12345;              // exponent = 4
    modulus = 256'd1000000007;               // modulus = 7 (odd prime)

    Np = 256'd14412540391571238400966997766934456954787576109662604465421775855956845362249;                    // 简化的Np
    R2_mod_N = 256'd418385479;              // 简化的R2_mod_N
 */ 
 
/*     base = 256'd1078961776455629576919318676217771327550228900422962782851421990960986252959;                    // base = 3
    exponent = 256'd2948121197;              // exponent = 4
    modulus = 256'd5220254616776520532222098534012283873947623957321046032249178903823549762503;               // modulus = 7 (odd prime)    // 计算 3^4 mod 7 = 81 mod 7 = 4
 
    Np = 256'd27315222822949966172335585716509223764439986641552652917951931124049428101641;                    // 简化的Np
    R2_mod_N = 256'd405151027066868242720436998929803906207071621759257568714114569842873813848;              // 简化的R2_mod_N 
 */ 
 
/*     base = 256'd2;                    // base = 3
    exponent = 256'd256;              // exponent = 4
    modulus = 256'd115792089210356248762697446949407573530086143415290314195533631308867097853951;               // modulus = 7 (odd prime)    // 计算 3^4 mod 7 = 81 mod 7 = 4
 
    Np = 256'd115792089210356248768974548684794254293921932838497980611635986753331132366849;                    // 简化的Np
    R2_mod_N = 256'd134799733323198995502561713907086292154532538166959272814710328655875;              // 简化的R2_mod_N 
 */ 

/*     base = 256'd10742904886944465619481175416051310030106174163095476252052785791159521705762;                    // base = 3
    exponent = 256'd785353454;              // exponent = 4
    modulus = 256'd12631299621042184641616558691993183645416234846693232092554863049244670719983;               // modulus = 7 (odd prime)

    Np = 256'd38489099736821220721954797719575732632001331243103303875196816747321995192561;                    // 简化的Np
    R2_mod_N = 256'd6537019988385007056152026678226918932229181775017498012542731098431761274632;              // 简化的R2_mod_N
 */ 


    base = 256'd9;                    // base = 3
    exponent = 256'd4;              // exponent = 4
    modulus = 256'd17;               // modulus = 7 (odd prime)

    Np = 256'd6811299366900952671974763824040465167839410862684739061144563765171360567055;                    // 简化的Np
    R2_mod_N = 256'd1;              // 简化的R2_mod_N

 
 
    // 启动计算
    #10 start = 1;
    #10 start = 0;
    
    // 等待计算完成
    wait(done);
    #10;
    
    $display("[%t] Test 1 Result: %h", $time, result);
    
    // 测试用例2：另一个测试
/*     $display("\n[%t] Test 2: Another modular exponentiation", $time);
    base = 256'h5;                    // base = 5
    exponent = 256'h3;               // exponent = 3
    modulus = 256'h13;               // modulus = 19 (odd prime)
 */    // 计算 5^3 mod 19 = 125 mod 19 = 11
    
    $display("\n[%t] Test 2: Another modular exponentiation", $time);
/* // 先复位
    reset_n = 0;
    #20 reset_n = 1;
    #10;
 */    
    base = 256'd123456789;                    // base = 3
    exponent = 256'd12345;              // exponent = 4
    modulus = 256'd1000000007;               // modulus = 7 (odd prime)    // 计算 3^4 mod 7 = 81 mod 7 = 4
 
    Np = 256'd14412540391571238400966997766934456954787576109662604465421775855956845362249;                    // 简化的Np
    R2_mod_N = 256'd418385479;              // 简化的R2_mod_N 
    
    
    
    
    
    
    // 启动计算
    #10 start = 1;
    #10 start = 0;
    
    // 等待计算完成
    wait(done);
    #10;
    
    $display("[%t] Test 2 Result: %h", $time, result);
    
    // 测试用例3：指数为0的情况
    $display("\n[%t] Test 3: Exponent is 0", $time);
/* // 先复位
    reset_n = 0;
    #20 reset_n = 1;
    #10;    
 */    
    base = 256'h7;
    exponent = 256'h0;               // exponent = 0
    modulus = 256'h11;               // modulus = 17
    // 计算 7^0 mod 17 = 1
    
    // 启动计算
    #10 start = 1;
    #10 start = 0;
    
    // 等待计算完成
    wait(done);
    #10;
    
    $display("[%t] Test 3 Result: %h", $time, result);
    
    // 完成所有测试
    #100;
    $display("\n[%t] All tests completed", $time);
    $finish;
end

// ================= 监控输出 =================
always @(posedge clk) begin
    if (done) begin
        $display("[%t] Calculation done: result = %h", $time, result);
    end
end

endmodule