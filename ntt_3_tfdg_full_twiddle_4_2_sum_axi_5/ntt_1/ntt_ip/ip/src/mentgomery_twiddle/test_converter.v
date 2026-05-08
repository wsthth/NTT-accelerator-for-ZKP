// test_converter.v
`timescale 1ns / 1ps

module test_converter;

reg clk;
reg reset_n;
reg start;
reg [255:0] normal_input;
reg [255:0] N;
reg [255:0] N_prime;
reg [255:0] R_mod_N;
reg [255:0] R2_mod_N;
reg direction;
wire [255:0] converted_output;
wire done;

montgomery_converter converter (
    .clk(clk),
    .reset_n(reset_n),
    .start(start),
    .normal_input(normal_input),
    .N(N),
    .N_prime(N_prime),
    .R_mod_N(R_mod_N),
    .R2_mod_N(R2_mod_N),
    .direction(direction),
    .converted_output(converted_output),
    .done(done)
);

always #5 clk = ~clk;

initial begin
    clk = 0;
    reset_n = 0;
    start = 0;
    normal_input = 0;
    N = 0;
    N_prime = 0;
    R_mod_N = 0;
    R2_mod_N = 0;
    direction = 0;
    
    // 复位
    #20 reset_n = 1;
    #50;
    
    // 测试1: 将2转换到蒙哥马利域 (N=5)
    $display("Test 1: Convert 2 to Montgomery domain (N=5)");
    normal_input = 256'd2;
    N = 256'd5;
    N_prime = 256'h3333333333333333333333333333333333333333333333333333333333333333;
    R_mod_N = 256'd1;      // 2^256 mod 5 = 1
    R2_mod_N = 256'd1;     // (2^256)^2 mod 5 = 1
    direction = 0;         // 普通域 -> 蒙哥马利域
    
    start = 1;
    #10 start = 0;
    wait(done);
    #10;
    
    $display("  2 in normal domain -> %064h in Montgomery domain", converted_output);
    $display("  Expected: 2 (because R=1 for N=5)");
    
    // 测试2: 将蒙哥马利域的2转换回普通域
    $display("\nTest 2: Convert back from Montgomery domain");
    normal_input = converted_output;  // 使用刚才得到的结果
    direction = 1;         // 蒙哥马利域 -> 普通域
    
    start = 1;
    #10 start = 0;
    wait(done);
    #10;
    
    $display("  %064h in Montgomery domain -> %064h in normal domain", 
             normal_input, converted_output);
    $display("  Expected: 2");
    
    #100;
    $finish;
end

endmodule

