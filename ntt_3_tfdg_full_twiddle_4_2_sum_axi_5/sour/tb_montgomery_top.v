`timescale 1ns/1ps
// ============================================================================
// Testbench for Montgomery Pipeline Module (Streaming Version)
// Multiple Test Cases for Vivado Simulation
// ============================================================================
module tb_montgomery_top;

localparam TOTAL_BITS = 256;
localparam SEG_BITS = 64;
localparam SEG_CNT = TOTAL_BITS / SEG_BITS;
localparam PIPELINE_STAGES = 6;

reg clk;
reg rst_n;
reg [TOTAL_BITS-1:0] N;
reg [TOTAL_BITS-1:0] N_prime;
reg [2*TOTAL_BITS-1:0] t;
reg in_valid;
wire in_ready;
wire [TOTAL_BITS-1:0] mont_result;
wire out_valid;

reg [31:0] cycle_count;
reg test_passed;
reg [TOTAL_BITS-1:0] result_check;

montgomery_pipeline #(
    .TOTAL_BITS(TOTAL_BITS),
    .SEG_BITS(SEG_BITS),
    .SEG_CNT(SEG_CNT),
    .PIPELINE_STAGES(PIPELINE_STAGES)
) u_montgomery (
    .clk(clk),
    .rst_n(rst_n),
    .N(N),
    .N_prime(N_prime),
    .t(t),
    .in_valid(in_valid),
    .in_ready(in_ready),
    .mont_result(mont_result),
    .out_valid(out_valid)
);

// ============================================================================
// Test Vectors
// ============================================================================
localparam [TOTAL_BITS-1:0] TEST_N = 256'h30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47;
localparam [TOTAL_BITS-1:0] TEST_N_PRIME = 256'hf57a22b791888c6bd8afcbd01833da809ede7d651eca6ac987d20782e4866389;

// Test 1: Small numbers
localparam [TOTAL_BITS-1:0] A_MONT_1 = 256'h04cda1728934ce7f2e06dd410c76ab667d9dd5aa5242e785f1cdd808dbea2eec;
localparam [TOTAL_BITS-1:0] B_MONT_1 = 256'h24db36a1a5c2b40b810f3e6473acf452df26a211fc84d6fa0fef05b7da276c7e;
localparam [2*TOTAL_BITS-1:0] T_1     = 512'h00b107a3a0c3af73ef0b6bc22956e42e5a20809bb025fdced181f58775503276c20873e5f857f6c741bc131ab4a7db89c6523449280c53bdb8b924792702a828;
localparam [TOTAL_BITS-1:0] EXP_1    = 256'h07cae7e16f3bff0918a549684a296b08ae1bcd93b09437ef7bbdfdf7d8dfa44d;

// Test 2: Original
localparam [TOTAL_BITS-1:0] A_MONT_2 = 256'h16db3787c008bbc00870a59497036f7f43e71fc1218341741c7bc7cc0ceb3313;
localparam [TOTAL_BITS-1:0] B_MONT_2 = 256'h087a1d2b7448c77d0c5a8c4e7241aa9a40f3f294768bdd2611e3d89374ff16f6;
localparam [2*TOTAL_BITS-1:0] T_2     = 512'h00c1c0cf6b3053366c04cc5be157a618a4b05dc32dbba48398976daccbcd6a4bf7692fac951ce65ecc6b353dff255768a7b9b946411649b0e73854861c53b642;
localparam [TOTAL_BITS-1:0] EXP_2    = 256'h04e9d49a4b94c32028fce7d8baa58b0b51fc666ce74426c75ce1f21c8cdd75c5;

// Test 3: N-1 * 2
localparam [TOTAL_BITS-1:0] A_MONT_3 = 256'h2259d6b14729c0fa51e1a247090812318d087f6872aabf4f68c3488912edefaa;
localparam [TOTAL_BITS-1:0] B_MONT_3 = 256'h1c14ef83340fbe5eccdd46def0f28c5814f1d651eb8e167ba6ba871b8b1e1b3a;
localparam [2*TOTAL_BITS-1:0] T_3     = 512'h03c4a2a3a406daf0d6b3dc9e5c0c5951c26be97dc4cf3eb20b055c5a3c2baf0cf77ad4f763b8590e953a3b5650a8744917865171acfac3b6183b39fec61b3a84;
localparam [TOTAL_BITS-1:0] EXP_3    = 256'h144f5eefad21e1caeb72fed7908ecc05828f943f7ce3b411956604fb4d5ee20d;

// Test 4: All ones * 1
localparam [TOTAL_BITS-1:0] A_MONT_4 = 256'h2932762311e1f619998cc1461349922842ef987a46efc14b5bf044e46678ea33;
localparam [TOTAL_BITS-1:0] B_MONT_4 = 256'h0e0a77c19a07df2f666ea36f7879462c0a78eb28f5c70b3dd35d438dc58f0d9d;
localparam [2*TOTAL_BITS-1:0] T_4     = 512'h024271b425180b667185b3099f5cda7ea0d4b25055789a9e8c3e378507830c99a0f0266aa90e2b5a60acc849f013e78cc9fb7ad2eb0439d707b57a220d893847;
localparam [TOTAL_BITS-1:0] EXP_4    = 256'h2932762311e1f619998cc1461349922842ef987a46efc14b5bf044e46678ea33;

// Test 5: Random
localparam [TOTAL_BITS-1:0] A_MONT_5 = 256'h1113fb2134cd327c8aa264fdee21d2b468f1b0420a3691034cf1d531fb21b7c6;
localparam [TOTAL_BITS-1:0] B_MONT_5 = 256'h204445a7929f30262a789fc08ff92c05ff77ca08d45bb7ce346bc4e118035620;
localparam [2*TOTAL_BITS-1:0] T_5     = 512'h02270d586bec768def8046a9e4828aea583a4a5a1a47aba6e45b095a0ac8ca8a91d83499c00a2f5bae85793b8b785fc7abfc2b372359b0089c12a8426f457cc0;
localparam [TOTAL_BITS-1:0] EXP_5    = 256'h1b872d1a794b66632eab713c3d5b739a525d9960bf9d095b9aad64de16297001;

// Test 6: 1 * (N-1)
localparam [TOTAL_BITS-1:0] A_MONT_6 = 256'h0e0a77c19a07df2f666ea36f7879462c0a78eb28f5c70b3dd35d438dc58f0d9d;
localparam [TOTAL_BITS-1:0] B_MONT_6 = 256'h2259d6b14729c0fa51e1a247090812318d087f6872aabf4f68c3488912edefaa;
localparam [2*TOTAL_BITS-1:0] T_6     = 512'h01e25151d2036d786b59ee4f2e062ca8e135f4bee2679f590582ae2d1e15d7867bbd6a7bb1dc2c874a9d1dab28543a248bc328b8d67d61db0c1d9cff630d9d42;
localparam [TOTAL_BITS-1:0] EXP_6    = 256'h2259d6b14729c0fa51e1a247090812318d087f6872aabf4f68c3488912edefaa;

localparam NUM_TESTS = 6;

reg [31:0] test_index;
reg [31:0] tests_passed;
reg [31:0] tests_failed;
reg [TOTAL_BITS-1:0] current_expected;
reg [TOTAL_BITS-1:0] result_queue [0:NUM_TESTS-1];
reg [TOTAL_BITS-1:0] expected_queue [0:NUM_TESTS-1];
reg [2*TOTAL_BITS-1:0] t_queue [0:NUM_TESTS-1];
reg [31:0] result_count;
reg [31:0] input_count;

always #5 clk = ~clk;

// ============================================================================
// Input Task for Streaming Pipeline
// ============================================================================
task send_input;
    input [2*TOTAL_BITS-1:0] test_t;
    begin
        wait(in_ready == 1);
        @(posedge clk);
        N = TEST_N;
        N_prime = TEST_N_PRIME;
        t = test_t;
        in_valid = 1;
        @(posedge clk);
        in_valid = 0;
    end
endtask

// ============================================================================
// Main Test Process
// ============================================================================
initial begin
    $display("======================================================================");
    $display("Montgomery Pipeline Testbench - Streaming Version");
    $display("======================================================================");
    $display("Testing Montgomery Modular Reduction with BN254 curve parameters");
    $display("TOTAL_BITS = %d, SEG_BITS = %d, SEG_CNT = %d", TOTAL_BITS, SEG_BITS, SEG_CNT);
    $display("PIPELINE_STAGES = %d", PIPELINE_STAGES);
    $display("Number of test cases: %d", NUM_TESTS);
    $display("======================================================================");

    clk = 0;
    rst_n = 0;
    N = 0;
    N_prime = 0;
    t = 0;
    in_valid = 0;
    cycle_count = 0;
    test_passed = 1;
    result_check = 0;
    test_index = 0;
    tests_passed = 0;
    tests_failed = 0;
    result_count = 0;
    input_count = 0;

    #20;
    rst_n = 1;
    #20;

    result_queue[0] = EXP_1;
    result_queue[1] = EXP_2;
    result_queue[2] = EXP_3;
    result_queue[3] = EXP_4;
    result_queue[4] = EXP_5;
    result_queue[5] = EXP_6;

    t_queue[0] = T_1;
    t_queue[1] = T_2;
    t_queue[2] = T_3;
    t_queue[3] = T_4;
    t_queue[4] = T_5;
    t_queue[5] = T_6;

    $display("\n[Pipeline] Sending test inputs...");
    $display("======================================================================");

    for (test_index = 0; test_index < NUM_TESTS; test_index = test_index + 1) begin
        $display("[Test %0d/%0d] Input sent - T = 0x%h...", 
                 test_index+1, NUM_TESTS, t_queue[test_index]);
        send_input(t_queue[test_index]);
        input_count = input_count + 1;
    end

    $display("\n[Pipeline] Waiting for results...");
    $display("======================================================================");

    for (test_index = 0; test_index < NUM_TESTS; test_index = test_index + 1) begin
        wait(out_valid == 1);
        @(posedge clk);
        result_check = mont_result;
        current_expected = result_queue[test_index];

        $display("\n[Result %0d/%0d]", test_index+1, NUM_TESTS);
        $display("Expected: 0x%h", current_expected);
        $display("Got:      0x%h", result_check);

        if (result_check == current_expected) begin
            $display("[Test %0d] PASS", test_index+1);
            tests_passed = tests_passed + 1;
        end else begin
            $display("[Test %0d] FAIL", test_index+1);
            tests_failed = tests_failed + 1;
        end
        result_count = result_count + 1;
        @(posedge clk);
    end

    $display("\n======================================================================");
    $display("Test Summary");
    $display("======================================================================");
    $display("Total Tests: %0d", NUM_TESTS);
    $display("Passed:     %0d", tests_passed);
    $display("Failed:     %0d", tests_failed);

    if (tests_failed == 0) begin
        $display("========================================");
        $display("[ALL TESTS PASSED]");
        $display("========================================");
    end else begin
        $display("========================================");
        $display("[SOME TESTS FAILED]");
        $display("========================================");
    end

    $display("======================================================================");

    #100;
    $finish;
end

initial begin
    $dumpfile("tb_montgomery_top.vcd");
    $dumpvars(0, tb_montgomery_top);
end

reg [31:0] timeout_counter;
initial begin
    timeout_counter = 0;
    wait(rst_n == 1);
    forever begin
        @(posedge clk);
        timeout_counter = timeout_counter + 1;
        if (timeout_counter > 100000) begin
            $display("[ERROR] Simulation timeout!");
            $finish;
        end
        if (out_valid) begin
            timeout_counter = 0;
        end
    end
end

endmodule
