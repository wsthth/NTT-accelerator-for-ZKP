`timescale 1ns/1ps
module tb_segmented_256bit_butterfly_1;

parameter TOTAL_WIDTH = 256;
parameter CLK_PERIOD = 10;

reg clk, rst_n, start;
reg [TOTAL_WIDTH-1:0] x0, x1, w, modulus, N_prime;
wire done, busy, result_valid;
wire [TOTAL_WIDTH-1:0] result_add, result_sub;

segmented_256bit_full_butterfly #(
    .TOTAL_WIDTH(TOTAL_WIDTH),
    .SEG_WIDTH(64),
    .SEG_COUNT(4)
) dut (
    .clk(clk), .rst_n(rst_n), .start(start),
    .done(done), .busy(busy),
    .x0(x0), .x1(x1), .w(w),
    .N_prime(N_prime), .modulus(modulus),
    .result_add(result_add), .result_sub(result_sub),
    .result_valid(result_valid)
);

always #(CLK_PERIOD/2) clk = ~clk;

// BN254 参数
localparam [TOTAL_WIDTH-1:0] BN_N  = 256'h30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47;
localparam [TOTAL_WIDTH-1:0] BN_NP = 256'hf57a22b791888c6bd8afcbd01833da809ede7d651eca6ac987d20782e4866389;

// ===== 测试向量（Python预计算，Montgomery形式） =====

// Test1: x0=1, 大数
localparam [TOTAL_WIDTH-1:0] T1_X0 = 256'h0000000000000000000000000000000000000000000000000000000000000001;
localparam [TOTAL_WIDTH-1:0] T1_X1 = 256'h2af6c90ca9c956dd6b98e311ccd63306d9d3afb7d1ae902b6da869a153471ff8;
localparam [TOTAL_WIDTH-1:0] T1_W  = 256'h25d71bdb3c5ed1475dd3a3192abc611b0e92ba5d5718e22b9fa3fab39975b753;
localparam [TOTAL_WIDTH-1:0] T1_EXP_ADD = 256'h0d78e11613448413eb757358b09cd34f2fd5e642421128797191dff87c5bd062;
localparam [TOTAL_WIDTH-1:0] T1_EXP_SUB = 256'h22eb6d5ccded1c15ccdad25dd0e4850e67ab844f2660a213ca8eac1e5c212ce7;

// Test2: 随机大数
localparam [TOTAL_WIDTH-1:0] T2_X0 = 256'h08ee307a392456de3eb13b9046685257bdd640fb06671ad11c80317fa3b1799d;
localparam [TOTAL_WIDTH-1:0] T2_X1 = 256'h25caa11a16419f828b9d2434e465e150bd9c66b3ad3c2d6d1a3d1fa7bc8960a9;
localparam [TOTAL_WIDTH-1:0] T2_W  = 256'h26877991815ef6d13b8faa1837f8a88b17fc695a07a0ca6e0822e8f36c031199;
localparam [TOTAL_WIDTH-1:0] T2_EXP_ADD = 256'h0b22f527747e027a168808f7e71800feceadc118e00f6d3d402591f0f6008698;
localparam [TOTAL_WIDTH-1:0] T2_EXP_SUB = 256'h06b96bccfdcaab4266da6e28a5b8a3b0acfec0dd2cbec864f8dad10e51626ca2;

// Test3: 随机大数
localparam [TOTAL_WIDTH-1:0] T3_X0 = 256'h1ad969a98b8148f6b38a088ca65ed389b74d0fb132e706298fadc1a606cb0fb3;
localparam [TOTAL_WIDTH-1:0] T3_X1 = 256'h0dc7b35e27cd813047229389571aa8766c307511b2b9437a28df6ec4ce4a2bbd;
localparam [TOTAL_WIDTH-1:0] T3_W  = 256'h16f984a318c267976142ea7d17be31111a2a73ed562b0f79c37459eef50bea63;
localparam [TOTAL_WIDTH-1:0] T3_EXP_ADD = 256'h2f7f4ff2c940d05c21561f09764cf19ab8af11fe9901dd29d2c5d722f71b4957;
localparam [TOTAL_WIDTH-1:0] T3_EXP_SUB = 256'h063383604dc1c19145bdf20fd670b578b5eb0d63cccc2f294c95ac29167ad60f;

// Test4: x0=0, 小数（Montgomery形式结果不为0）
localparam [TOTAL_WIDTH-1:0] T4_X0 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
localparam [TOTAL_WIDTH-1:0] T4_X1 = 256'h0000000000000000000000000000000000000000000000000000000000000007;
localparam [TOTAL_WIDTH-1:0] T4_W  = 256'h000000000000000000000000000000000000000000000000000000000000000d;
localparam [TOTAL_WIDTH-1:0] T4_EXP_ADD = 256'h0c8df6406cd0085f153c6bd0226b2ba817710ddd6250c17cff0cd68ae32cde6c;
localparam [TOTAL_WIDTH-1:0] T4_EXP_SUB = 256'h23d65832746197caa313d9e65f162cb580105cb4062109103d13b58bf5501edb;

// Test5: x0=N-1, x1=1, w=1
localparam [TOTAL_WIDTH-1:0] T5_X0 = 256'h30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd46;
localparam [TOTAL_WIDTH-1:0] T5_X1 = 256'h0000000000000000000000000000000000000000000000000000000000000001;
localparam [TOTAL_WIDTH-1:0] T5_W  = 256'h0000000000000000000000000000000000000000000000000000000000000001;
localparam [TOTAL_WIDTH-1:0] T5_EXP_ADD = 256'h2e67157159e5c639cf63e9cfb74492d9eb2022850278edf8ed84884a014afa36;
localparam [TOTAL_WIDTH-1:0] T5_EXP_SUB = 256'h01fd3901874bd9efe8ec5be6ca3cc583ac61480c65f8dc944e9c03ccd732030f;

// Test6: 随机1
localparam [TOTAL_WIDTH-1:0] T6_X0 = 256'h088713803f9931ee3af27f802dc5fd3d9974d75b333824fe61790134676b1b69;
localparam [TOTAL_WIDTH-1:0] T6_X1 = 256'h2cd4cc73af2ed9dd87e355b26210b784baa1c6f1404b6eaf162a01dec28753f8;
localparam [TOTAL_WIDTH-1:0] T6_W  = 256'h2e38f1c76bf08d62331057ca7d411fab9fb932d4f039772216ff82e389e3995a;
localparam [TOTAL_WIDTH-1:0] T6_EXP_ADD = 256'h2cf75cdfc10f7ba373ba410814c6446fb212629ad6a5ad42ac68da9f0e26dcfb;
localparam [TOTAL_WIDTH-1:0] T6_EXP_SUB = 256'h147b18939f548862ba7b03aec8470e691858b6acf83c674752a9b3e0992c571e;

integer pass_count, fail_count;
integer cycle_cnt;

task check_and_report;
    input [TOTAL_WIDTH-1:0] exp_add, exp_sub;
    input integer tnum;
begin
    if (result_add == exp_add && result_sub == exp_sub) begin
        $display("  Test %0d: PASS", tnum);
        pass_count = pass_count + 1;
    end else begin
        $display("  Test %0d: FAIL", tnum);
        $display("    exp_add=0x%064h", exp_add);
        $display("    got_add=0x%064h", result_add);
        $display("    exp_sub=0x%064h", exp_sub);
        $display("    got_sub=0x%064h", result_sub);
        fail_count = fail_count + 1;
    end
end
endtask

task run_test;
    input [TOTAL_WIDTH-1:0] t_x0, t_x1, t_w;
    input [TOTAL_WIDTH-1:0] t_exp_add, t_exp_sub;
    input integer tnum;
begin
    @(negedge clk);
    x0 = t_x0; x1 = t_x1; w = t_w;
    start = 1;
    @(negedge clk);
    start = 0;
    // 等2个posedge让状态机锁存mont_t_r
    @(posedge clk);
    @(posedge clk);
    $display("  [DBG] mont_t_r  =0x%0128h", dut.mont_t_r);
    $display("  [DBG] full_prod =0x%0128h", dut.full_product);
    wait(result_valid);
    @(posedge clk);
    check_and_report(t_exp_add, t_exp_sub, tnum);
    #(CLK_PERIOD * 3);
end
endtask

initial begin
    clk = 0; rst_n = 0; start = 0;
    x0 = 0; x1 = 0; w = 0;
    modulus = BN_N; N_prime = BN_NP;
    pass_count = 0; fail_count = 0;
    cycle_cnt = 0;

    #100; rst_n = 1; #(CLK_PERIOD * 5);

    $display("=== Butterfly Test (BN254, Montgomery) ===");
    run_test(T1_X0, T1_X1, T1_W, T1_EXP_ADD, T1_EXP_SUB, 1);
    run_test(T2_X0, T2_X1, T2_W, T2_EXP_ADD, T2_EXP_SUB, 2);
    run_test(T3_X0, T3_X1, T3_W, T3_EXP_ADD, T3_EXP_SUB, 3);
    run_test(T4_X0, T4_X1, T4_W, T4_EXP_ADD, T4_EXP_SUB, 4);
    run_test(T5_X0, T5_X1, T5_W, T5_EXP_ADD, T5_EXP_SUB, 5);
    run_test(T6_X0, T6_X1, T6_W, T6_EXP_ADD, T6_EXP_SUB, 6);

    $display("");
    $display("=== Result: PASS=%0d  FAIL=%0d ===", pass_count, fail_count);
    if (fail_count == 0)
        $display("  ALL TESTS PASSED");
    $finish;
end

always @(posedge clk) begin
    if (rst_n) cycle_cnt = cycle_cnt + 1;
end

initial begin
    #200000; $display("TIMEOUT"); $finish;
end

endmodule
