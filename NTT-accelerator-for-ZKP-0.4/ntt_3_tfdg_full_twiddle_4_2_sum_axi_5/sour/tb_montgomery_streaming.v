`timescale 1ns/1ps
module tb_montgomery_streaming;

localparam TOTAL_BITS = 256;
localparam SEG_BITS   = 64;
localparam SEG_CNT    = TOTAL_BITS / SEG_BITS;
localparam PIPELINE_STAGES = 4;
localparam NUM_TESTS  = 8;

reg clk;
reg rst_n;
reg start;
reg [TOTAL_BITS-1:0] N;
reg [TOTAL_BITS-1:0] N_prime;
reg [2*TOTAL_BITS-1:0] t;

wire [TOTAL_BITS-1:0] mont_result;
wire valid_out;
wire done;

montgomery_pipeline #(
    .TOTAL_BITS(TOTAL_BITS),
    .SEG_BITS(SEG_BITS),
    .SEG_CNT(SEG_CNT),
    .PIPELINE_STAGES(PIPELINE_STAGES)
) u_montgomery (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .N(N),
    .N_prime(N_prime),
    .t(t),
    .mont_result(mont_result),
    .valid_out(valid_out),
    .done(done)
);

always #5 clk = ~clk;

localparam [TOTAL_BITS-1:0] TEST_N       = 256'h30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47;
localparam [TOTAL_BITS-1:0] TEST_N_PRIME = 256'hf57a22b791888c6bd8afcbd01833da809ede7d651eca6ac987d20782e4866389;

reg [2*TOTAL_BITS-1:0] test_t   [0:7];
reg [TOTAL_BITS-1:0]   test_exp [0:7];

initial begin
    test_t[0] = 512'h00b107a3a0c3af73ef0b6bc22956e42e5a20809bb025fdced181f58775503276c20873e5f857f6c741bc131ab4a7db89c6523449280c53bdb8b924792702a828;
    test_exp[0] = 256'h07cae7e16f3bff0918a549684a296b08ae1bcd93b09437ef7bbdfdf7d8dfa44d;
    test_t[1] = 512'h00c1c0cf6b3053366c04cc5be157a618a4b05dc32dbba48398976daccbcd6a4bf7692fac951ce65ecc6b353dff255768a7b9b946411649b0e73854861c53b642;
    test_exp[1] = 256'h04e9d49a4b94c32028fce7d8baa58b0b51fc666ce74426c75ce1f21c8cdd75c5;
    test_t[2] = 512'h03c4a2a3a406daf0d6b3dc9e5c0c5951c26be97dc4cf3eb20b055c5a3c2baf0cf77ad4f763b8590e953a3b5650a8744917865171acfac3b6183b39fec61b3a84;
    test_exp[2] = 256'h144f5eefad21e1caeb72fed7908ecc05828f943f7ce3b411956604fb4d5ee20d;
    test_t[3] = 512'h024271b425180b667185b3099f5cda7ea0d4b25055789a9e8c3e378507830c99a0f0266aa90e2b5a60acc849f013e78cc9fb7ad2eb0439d707b57a220d893847;
    test_exp[3] = 256'h2932762311e1f619998cc1461349922842ef987a46efc14b5bf044e46678ea33;
    test_t[4] = 512'h02270d586bec768def8046a9e4828aea583a4a5a1a47aba6e45b095a0ac8ca8a91d83499c00a2f5bae85793b8b785fc7abfc2b372359b0089c12a8426f457cc0;
    test_exp[4] = 256'h1b872d1a794b66632eab713c3d5b739a525d9960bf9d095b9aad64de16297001;
    test_t[5] = 512'h01e25151d2036d786b59ee4f2e062ca8e135f4bee2679f590582ae2d1e15d7867bbd6a7bb1dc2c874a9d1dab28543a248bc328b8d67d61db0c1d9cff630d9d42;
    test_exp[5] = 256'h2259d6b14729c0fa51e1a247090812318d087f6872aabf4f68c3488912edefaa;
    test_t[6] = test_t[0];
    test_exp[6] = test_exp[0];
    test_t[7] = test_t[1];
    test_exp[7] = test_exp[1];
end

integer cycle;
integer send_idx;
integer i;

// Collect all outputs into a buffer, then analyze afterward
reg [TOTAL_BITS-1:0] captured [0:15];
integer cap_count;

always @(posedge clk) begin
    if (rst_n) cycle = cycle + 1;
end

initial begin
    clk = 0;
    rst_n = 0;
    start = 0;
    N = 0;
    N_prime = 0;
    t = 0;
    cycle = 0;
    send_idx = 0;
    cap_count = 0;

    #25;
    rst_n = 1;
    #10;

    N = TEST_N;
    N_prime = TEST_N_PRIME;

    // Drive inputs on negedge to avoid race with pipeline's posedge sampling
    for (send_idx = 0; send_idx < NUM_TESTS; send_idx = send_idx + 1) begin
        @(negedge clk);
        start = 1;
        t = test_t[send_idx];
    end
    @(negedge clk);
    start = 0;

    // Drain pipeline for 20 cycles
    repeat (20) @(posedge clk);

    // Now analyze captured outputs
    $display("");
    $display("=== Captured %0d outputs ===", cap_count);
    for (i = 0; i < cap_count; i = i + 1) begin
        $display("  out[%0d] = 0x%0h", i, captured[i]);
    end

    // Find which input each output corresponds to
    $display("");
    $display("=== Matching outputs to expected ===");
    for (i = 0; i < cap_count; i = i + 1) begin
        if (captured[i] == test_exp[0])
            $display("  out[%0d] = test_exp[0] (input 0)  PASS", i);
        else if (captured[i] == test_exp[1])
            $display("  out[%0d] = test_exp[1] (input 1)  PASS", i);
        else if (captured[i] == test_exp[2])
            $display("  out[%0d] = test_exp[2] (input 2)  PASS", i);
        else if (captured[i] == test_exp[3])
            $display("  out[%0d] = test_exp[3] (input 3)  PASS", i);
        else if (captured[i] == test_exp[4])
            $display("  out[%0d] = test_exp[4] (input 4)  PASS", i);
        else if (captured[i] == test_exp[5])
            $display("  out[%0d] = test_exp[5] (input 5)  PASS", i);
        else if (captured[i] == test_exp[6])
            $display("  out[%0d] = test_exp[6] (input 6)  PASS", i);
        else if (captured[i] == test_exp[7])
            $display("  out[%0d] = test_exp[7] (input 7)  PASS", i);
        else
            $display("  out[%0d] = UNKNOWN              0x%0h  FAIL", i, captured[i]);
    end

    // Verify: all 8 inputs should produce all 8 expected outputs
    $display("");
    $display("=== Streaming Pipeline Result ===");
    if (cap_count == NUM_TESTS) begin
        $display("  Output count: %0d (expected %0d) - MATCH", cap_count, NUM_TESTS);
    end else begin
        $display("  Output count: %0d (expected %0d) - MISMATCH", cap_count, NUM_TESTS);
    end

    $display("");
    $finish;
end

// Capture outputs whenever valid_out is high
always @(posedge clk) begin
    if (valid_out) begin
        captured[cap_count] = mont_result;
        cap_count = cap_count + 1;
        $display("[CAP] C%0d: vo=1 mont=0x%0h", cycle, mont_result);
    end
end

initial begin
    #50000;
    $display("TIMEOUT");
    $finish;
end

endmodule
