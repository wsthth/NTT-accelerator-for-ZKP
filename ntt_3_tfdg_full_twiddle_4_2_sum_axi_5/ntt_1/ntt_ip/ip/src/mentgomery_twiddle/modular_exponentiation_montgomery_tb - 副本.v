// modular_exponentiation_montgomery_tb.v
`timescale 1ns / 1ps

module modular_exponentiation_montgomery_tb;

// ==================== Parameter Definitions ====================
parameter TOTAL_BITS = 256;
parameter EXP_BITS = 32;
parameter CLK_PERIOD = 10;  // 10ns -> 100MHz

// ==================== Signal Definitions ====================
reg clk;
reg reset_n;
reg start;

// Input signals
reg [TOTAL_BITS-1:0] base;
reg [EXP_BITS-1:0] exponent;
reg [TOTAL_BITS-1:0] N;
reg [TOTAL_BITS-1:0] N_prime;
reg [TOTAL_BITS-1:0] R_mod_N;
reg [TOTAL_BITS-1:0] R2_mod_N;

// Output signals
wire [TOTAL_BITS-1:0] result;
wire done;

// Test case parameters
reg [TOTAL_BITS-1:0] expected_result;
integer test_case_num;
integer pass_count;
integer fail_count;

// Debug counters
integer cycle_count;
integer timeout_counter;

// ==================== DUT Instantiation ====================
modular_exponentiation_montgomery #(
    .TOTAL_BITS(TOTAL_BITS),
    .EXP_BITS(EXP_BITS)
) dut (
    .clk(clk),
    .reset_n(reset_n),
    .start(start),
    
    // Input (normal domain)
    .base(base),
    .exponent(exponent),
    
    // Modulus and precomputed parameters
    .N(N),
    .N_prime(N_prime),
    .R_mod_N(R_mod_N),
    .R2_mod_N(R2_mod_N),
    
    // Output (normal domain)
    .result(result),
    .done(done)
);

// ==================== Clock Generation ====================
initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

// ==================== Cycle Counter ====================
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        cycle_count <= 0;
    end else if (start) begin
        cycle_count <= 0;
    end else if (!done) begin
        cycle_count <= cycle_count + 1;
    end
end

// ==================== Timeout Counter ====================
always @(posedge clk) begin
    if (start) begin
        timeout_counter <= 0;
    end else if (!done) begin
        timeout_counter <= timeout_counter + 1;
    end
end

// ==================== Reset Task ====================
task reset_system;
    begin
        reset_n = 0;
        start = 0;
        base = 0;
        exponent = 0;
        N = 0;
        N_prime = 0;
        R_mod_N = 0;
        R2_mod_N = 0;
        cycle_count = 0;
        timeout_counter = 0;
        #100;
        reset_n = 1;
        #100;
    end
endtask

// ==================== Main Test Process ====================
initial begin
    // Initialization
    $display("\n\n");
    $display("========================================");
    $display("Start Modular Exponentiation Module Test");
    $display("Time: %0t ns", $time);
    $display("========================================");
    
    reset_system();
    pass_count = 0;
    fail_count = 0;
    test_case_num = 0;
    
    // ==================== Test Case 1: Simple Modular Exponentiation ====================
    // Calculate 2^3 mod 5 = 8 mod 5 = 3
    test_case_num = test_case_num + 1;
    $display("\n========== Test Case %0d: 2^3 mod 5 = 3 ==========", test_case_num);
    $display("Time: %0t ns", $time);
    
    // Set test parameters
    base = {{(TOTAL_BITS-3){1'b0}}, 3'd2};  // base = 2
    exponent = 32'd3;                       // exponent = 3
    N = {{(TOTAL_BITS-3){1'b0}}, 3'd5};     // N = 5
    N_prime = 256'hcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccd;  // N_prime
    R_mod_N = {{(TOTAL_BITS-1){1'b0}}, 1'b1};  // R_mod_N = 1
    R2_mod_N = {{(TOTAL_BITS-1){1'b0}}, 1'b1}; // R2_mod_N = 1
    expected_result = {{(TOTAL_BITS-3){1'b0}}, 3'd3};  // expected: 2^3 mod 5 = 3
    
    // Start test
    start = 1;
    #100
    @(posedge clk);
    start = 0;
    
    // Wait for completion with timeout
    while (!done && timeout_counter < 1000) begin
        @(posedge clk);
    end
    
    if (done) begin
        $display("Test completed in %0d cycles", cycle_count);
        if (result === expected_result) begin
            $display("Test PASSED: result = %h", result);
            pass_count = pass_count + 1;
        end else begin
            $display("Test FAILED");
            $display("  Expected: %h", expected_result);
            $display("  Actual:   %h", result);
            fail_count = fail_count + 1;
        end
    end else begin
        $display("Test FAILED - Timeout after %0d cycles", timeout_counter);
        fail_count = fail_count + 1;
    end
    
    $display("Completion Time: %0t ns", $time);
    $display("=====================================");
    #100;
    
    // ==================== Test Case 2: Simple test with small values ====================
    // Calculate 1^5 mod 7 = 1
    test_case_num = test_case_num + 1;
    $display("\n========== Test Case %0d: 1^5 mod 7 = 1 ==========", test_case_num);
    $display("Time: %0t ns", $time);
    
    // Set test parameters
    base = {{(TOTAL_BITS-1){1'b0}}, 1'b1};  // base = 1
    exponent = 32'd5;                       // exponent = 5
    N = {{(TOTAL_BITS-3){1'b0}}, 3'd7};     // N = 7
    N_prime = 256'h9249249249249249249249249249249249249249249249249249249249249249;  // N_prime
    R_mod_N = {{(TOTAL_BITS-1){1'b0}}, 1'b1};  // R_mod_N = 1
    R2_mod_N = {{(TOTAL_BITS-1){1'b0}}, 1'b1}; // R2_mod_N = 1
    expected_result = {{(TOTAL_BITS-1){1'b0}}, 1'b1};  // expected: 1^5 mod 7 = 1
    
    // Start test
    start = 1;
    #100

    @(posedge clk);
    start = 0;
    
    // Wait for completion with timeout
    timeout_counter = 0;
    while (!done && timeout_counter < 1000) begin
        @(posedge clk);
    end
    
    if (done) begin
        $display("Test completed in %0d cycles", cycle_count);
        if (result === expected_result) begin
            $display("Test PASSED: result = %h", result);
            pass_count = pass_count + 1;
        end else begin
            $display("Test FAILED");
            $display("  Expected: %h", expected_result);
            $display("  Actual:   %h", result);
            fail_count = fail_count + 1;
        end
    end else begin
        $display("Test FAILED - Timeout after %0d cycles", timeout_counter);
        fail_count = fail_count + 1;
    end
    
    $display("Completion Time: %0t ns", $time);
    $display("=====================================");
    #100;
    
    // ==================== Test Case 3: Zero exponent ====================
    // Calculate 5^0 mod 11 = 1
    test_case_num = test_case_num + 1;
    $display("\n========== Test Case %0d: 5^0 mod 11 = 1 ==========", test_case_num);
    $display("Time: %0t ns", $time);
    
    // Set test parameters
    base = {{(TOTAL_BITS-4){1'b0}}, 4'd5};   // base = 5
    exponent = 32'd0;                        // exponent = 0
    N = {{(TOTAL_BITS-4){1'b0}}, 4'd11};     // N = 11
    N_prime = 256'he38e38e38e38e38e38e38e38e38e38e38e38e38e38e38e38e38e38e38e38e38e38e;  // N_prime
    R_mod_N = {{(TOTAL_BITS-1){1'b0}}, 1'b1};  // R_mod_N = 1
    R2_mod_N = {{(TOTAL_BITS-1){1'b0}}, 1'b1}; // R2_mod_N = 1
    expected_result = {{(TOTAL_BITS-1){1'b0}}, 1'b1};  // expected: 5^0 mod 11 = 1
    
    // Start test
    start = 1;
    #100
    @(posedge clk);
    start = 0;
    
    // Wait for completion with timeout
    timeout_counter = 0;
    while (!done && timeout_counter < 1000) begin
        @(posedge clk);
    end
    
    if (done) begin
        $display("Test completed in %0d cycles", cycle_count);
        if (result === expected_result) begin
            $display("Test PASSED: result = %h", result);
            pass_count = pass_count + 1;
        end else begin
            $display("Test FAILED");
            $display("  Expected: %h", expected_result);
            $display("  Actual:   %h", result);
            fail_count = fail_count + 1;
        end
    end else begin
        $display("Test FAILED - Timeout after %0d cycles", timeout_counter);
        fail_count = fail_count + 1;
    end
    
    $display("Completion Time: %0t ns", $time);
    $display("=====================================");
    #100;
    
    // ==================== Test Summary ====================
    $display("\n\n");
    $display("========================================");
    $display("Test Summary");
    $display("Total Test Cases: %0d", test_case_num);
    $display("Passed: %0d", pass_count);
    $display("Failed: %0d", fail_count);
    
    if (test_case_num != 0) begin
        $display("Pass Rate: %0.2f%%", (pass_count * 100.0) / test_case_num);
    end else begin
        $display("Pass Rate: N/A (no test cases)");
    end
    
    if (fail_count == 0) begin
        $display("All test cases PASSED!");
    end else begin
        $display("Some test cases FAILED, please check the design.");
    end
    
    $display("Total Test Time: %0t ns", $time);
    $display("========================================");
    
    // End simulation
    #100;
    $finish;
end

// ==================== Waveform Output ====================
initial begin
    // VCD file output for debugging
    $dumpfile("modular_exponentiation_montgomery_tb.vcd");
    $dumpvars(0, modular_exponentiation_montgomery_tb);
    
    // Set timeout protection (10ms)
    #10000000;
    $display("\n\n========================================");
    $display("Simulation Timeout at %0t ns!", $time);
    $display("This may indicate that the DUT is not working correctly.");
    $display("========================================");
    $finish;
end

// ==================== Monitor ====================
always @(posedge clk) begin
    // Monitor start signal
    if (start) begin
        $display("[%0t ns] Test started: base=%h, exponent=%h, N=%h", 
                $time, base, exponent, N);
    end
    
    // Monitor done signal
    if (done) begin
        $display("[%0t ns] Calculation completed: result=%h, cycle_count=%0d", 
                $time, result, cycle_count);
    end
end

endmodule