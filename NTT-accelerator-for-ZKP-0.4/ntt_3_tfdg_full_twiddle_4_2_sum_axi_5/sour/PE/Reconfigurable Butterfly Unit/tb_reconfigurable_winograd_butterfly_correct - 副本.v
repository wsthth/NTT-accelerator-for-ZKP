// ============================================================================
// File Name: tb_reconfigurable_winograd_butterfly_correct.v
// Description: Corrected butterfly engine testbench (with proper twiddle factor calculation)
// ============================================================================
`timescale 1ns/1ps

module tb_reconfigurable_winograd_butterfly_correct;

// Test parameters
parameter DATA_WIDTH = 128;
parameter MAX_RADIX = 4;
parameter MULT_ARRAY_SIZE = 4;
parameter EXP_WIDTH = 8;

// Clock and reset signals
reg clk;
reg rst_n;

// Module inputs
reg start;
reg [3:0] radix_cfg;
reg [1:0] width_cfg;
reg [DATA_WIDTH-1:0] x_in [0:MAX_RADIX-1];
reg [DATA_WIDTH-1:0] twiddle_base;
reg [DATA_WIDTH-1:0] modulus;
reg [DATA_WIDTH-1:0] N_prime;
reg [DATA_WIDTH-1:0] R2_mod_N;

// Module outputs
wire [DATA_WIDTH*MAX_RADIX-1:0] x_out_flat_wire;
wire done;
wire valid;

// Test control
integer test_num;
integer pass_count;
integer fail_count;
reg test_pass;

// Expected results array
reg [DATA_WIDTH-1:0] expected [0:MAX_RADIX-1];

// Instantiate DUT
reconfigurable_winograd_butterfly #(
    .DATA_WIDTH(DATA_WIDTH),
    .MAX_RADIX(MAX_RADIX),
    .MULT_ARRAY_SIZE(MULT_ARRAY_SIZE),
    .EXP_WIDTH(EXP_WIDTH)
) uut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .radix_cfg(radix_cfg),
    .width_cfg(width_cfg),
.x_in_flat({x_in[3], x_in[2], x_in[1], x_in[0]}),
    .twiddle_base(twiddle_base),
    .modulus(modulus),
    .N_prime(N_prime),
    .R2_mod_N(R2_mod_N),
.x_out_flat(x_out_flat_wire),
    .done(done),
    .valid(valid)
);
wire [DATA_WIDTH-1:0] x_out_array [0:MAX_RADIX-1];
assign x_out_array[0] = x_out_flat_wire[0*DATA_WIDTH +: DATA_WIDTH];
assign x_out_array[1] = x_out_flat_wire[1*DATA_WIDTH +: DATA_WIDTH];
assign x_out_array[2] = x_out_flat_wire[2*DATA_WIDTH +: DATA_WIDTH];
assign x_out_array[3] = x_out_flat_wire[3*DATA_WIDTH +: DATA_WIDTH];
// Clock generation
initial begin
    clk = 0;
    forever #5 clk = ~clk;  // 100MHz clock
end

// ============================================================================
// Helper functions: Modular exponentiation (for verification)
// ============================================================================
function [DATA_WIDTH-1:0] mod_exp;
    input [DATA_WIDTH-1:0] base;
    input [EXP_WIDTH-1:0] exp;
    input [DATA_WIDTH-1:0] mod;
    integer i;
    reg [DATA_WIDTH-1:0] result;
    begin
        result = 1;
        for (i = 0; i < exp; i = i + 1) begin
            result = (result * base) % mod;
        end
        mod_exp = result;
    end
endfunction

// Calculate WNTT coefficient matrix
function [DATA_WIDTH-1:0] calculate_coeff;
    input [3:0] k, j;
    input [3:0] radix;
    input [DATA_WIDTH-1:0] omega;
    input [DATA_WIDTH-1:0] mod;
    reg [7:0] exp;
    begin
        exp = (j * k) % radix;  // j*k mod r
        calculate_coeff = mod_exp(omega, exp, mod);
    end
endfunction

// ============================================================================
// Test case: Radix-2 test (with twiddle factor)
// ============================================================================
task test_radix2_with_twiddle;
    input [DATA_WIDTH-1:0] x0, x1;
    input [DATA_WIDTH-1:0] omega;
    input [DATA_WIDTH-1:0] mod;
    
    integer k, j;
    reg [DATA_WIDTH-1:0] coeff;
    reg [DATA_WIDTH-1:0] acc;
    begin
        test_num = test_num + 1;
        $display("\n[Test %0d] Radix-2 test (ω=%h)", test_num, omega);
        $display("Input: x0=%h, x1=%h", x0, x1);
        $display("Modulus: %h", mod);
        
        // Configure radix-2
        radix_cfg = 4'd2;
        modulus = mod;
        N_prime = 128'h1;   // Simplified parameter
        R2_mod_N = 128'h1;  // Simplified parameter
        twiddle_base = omega;
        
        // Set input data
        x_in[0] = x0;
        x_in[1] = x1;

        //th
        expected[0]=0;
        expected[1]=0;
        expected[2]=0;
        expected[3]=0;
        // Calculate expected results
        $display("Expected results:");
        
        for (k = 0; k < 2; k = k + 1) begin
            acc = 0;
            for (j = 0; j < 2; j = j + 1) begin
                // Calculate coefficient ω^(j*k mod r)
                coeff = calculate_coeff(k, j, 2, omega, mod);
                // Accumulate x[j] * coeff
                acc = (acc + (x_in[j] * coeff) % mod) % mod;
            end
            expected[k] = acc;
            $display("  X[%0d] = %h", k, expected[k]);
        end
        
        // Start computation
        start = 1;
        #10 start = 0;
        
        // Wait for completion
        wait(done);
        #20;  // Wait some cycles
        
        // Check results
        test_pass = (x_out_array[0] === expected[0]) && (x_out_array[1] === expected[1]);
        
        if (test_pass) begin
            pass_count = pass_count + 1;
            $display("✓ Test PASSED");
            $display("  Actual output: X[0]=%h, X[1]=%h", x_out_array[0], x_out_array[1]);
        end else begin
            fail_count = fail_count + 1;
            $display("✗ Test FAILED");
            $display("  Expected: %h, %h", expected[0], expected[1]);
            $display("  Actual: %h, %h", x_out_array[0], x_out_array[1]);
        end
        
        // Wait one cycle
        #20;
    end
endtask

// ============================================================================
// Test case: Radix-4 test (with twiddle factor)
// ============================================================================
task test_radix4_with_twiddle;
    input [DATA_WIDTH-1:0] x0, x1, x2, x3;
    input [DATA_WIDTH-1:0] omega;
    input [DATA_WIDTH-1:0] mod;
    
    integer k, j;
    reg [DATA_WIDTH-1:0] coeff;
    reg [DATA_WIDTH-1:0] acc;
    begin
        test_num = test_num + 1;
        $display("\n[Test %0d] Radix-4 test (ω=%h)", test_num, omega);
        $display("Input: x0=%h, x1=%h, x2=%h, x3=%h", x0, x1, x2, x3);
        $display("Modulus: %h", mod);
        
        // Configure radix-4
        radix_cfg = 4'd4;
        modulus = mod;
        N_prime = 128'h1;   // Simplified parameter
        R2_mod_N = 128'h1;  // Simplified parameter
        twiddle_base = omega;
        
        // Set input data
        x_in[0] = x0;
        x_in[1] = x1;
        x_in[2] = x2;
        x_in[3] = x3;
        
        //th
        expected[0]=0;
        expected[1]=0;
        expected[2]=0;
        expected[3]=0;
        
        
        // Calculate expected results
        $display("Expected results:");
        
        for (k = 0; k < 4; k = k + 1) begin
            acc = 0;
            for (j = 0; j < 4; j = j + 1) begin
                // Calculate coefficient ω^(j*k mod r)
                coeff = calculate_coeff(k, j, 4, omega, mod);
                // Accumulate x[j] * coeff
                acc = (acc + (x_in[j] * coeff) % mod) % mod;
            end
            expected[k] = acc;
            $display("  X[%0d] = %h", k, expected[k]);
        end
        
        // Start computation
        start = 1;
        #10 start = 0;
        
        // Wait for completion
        wait(done);
        #20;  // Wait some cycles
        
        // Check results
        test_pass = (x_out_array[0] === expected[0]) && 
                   (x_out_array[1] === expected[1]) &&
                   (x_out_array[2] === expected[2]) &&
                   (x_out_array[3] === expected[3]);
        
        if (test_pass) begin
            pass_count = pass_count + 1;
            $display("✓ Test PASSED");
            $display("  Actual output: X[0]=%h, X[1]=%h, X[2]=%h, X[3]=%h",
                     x_out_array[0], x_out_array[1], x_out_array[2], x_out_array[3]);
        end else begin
            fail_count = fail_count + 1;
            $display("✗ Test FAILED");
            $display("  Expected: %h, %h, %h, %h", 
                    expected[0], expected[1], expected[2], expected[3]);
            $display("  Actual: %h, %h, %h, %h", 
                    x_out_array[0], x_out_array[1], x_out_array[2], x_out_array[3]);
        end
        
        // Wait one cycle
        #20;
    end
endtask

// ============================================================================
// Run all tests
// ============================================================================
task run_all_tests;
    reg [DATA_WIDTH-1:0] mod17;
    reg [DATA_WIDTH-1:0] mod23;
    begin
        mod17 = 128'h11;  // 17
        mod23 = 128'h17;  // 23
        
        $display("==================================================");
        $display("Starting tests for reconfigurable_winograd_butterfly");
        $display("With correct twiddle factor calculation verification");
        $display("==================================================");
        
        // Test 1: Radix-2, ω=16 mod 17 (ω^2 ≡ 1 mod 17)
        test_radix2_with_twiddle(128'h1, 128'h2, 128'h10, mod17);
        
        // Test 2: Radix-2, ω=9 mod 17 (ω^2 ≡ 13 mod 17)
        test_radix2_with_twiddle(128'h3, 128'h5, 128'h9, mod17);
        
        // Test 3: Radix-2 boundary test
        test_radix2_with_twiddle(128'h0, 128'h0, 128'h10, mod17);
        
        // Test 4: Radix-2 modulo boundary test
        test_radix2_with_twiddle(128'h10, 128'h10, 128'h10, mod17);
        
        // Test 5: Radix-4, ω=4 mod 17 (ω^4 ≡ 1 mod 17)
        test_radix4_with_twiddle(128'h1, 128'h2, 128'h3, 128'h4, 128'h4, mod17);
        
        // Test 6: Radix-4, ω=2 mod 17
        test_radix4_with_twiddle(128'h1, 128'h3, 128'h5, 128'h7, 128'h2, mod17);
        
        // Test 7: Radix-4 zero input test
        test_radix4_with_twiddle(128'h0, 128'h0, 128'h0, 128'h0, 128'h4, mod17);
        
        $display("\nTest suite execution completed");
    end
endtask

// ============================================================================
// Main test flow
// ============================================================================
    integer i;

initial begin
    
    // Initialize test counters
    test_num = 0;
    pass_count = 0;
    fail_count = 0;
    
    // Initialize input signals
    rst_n = 0;
    start = 0;
    radix_cfg = 0;
    width_cfg = 0;
    twiddle_base = 0;
    modulus = 0;
    N_prime = 0;
    R2_mod_N = 0;
        //th
        expected[0]=0;
        expected[1]=0;
        expected[2]=0;
        expected[3]=0;
        
        test_pass =0;
    // Initialize input array
    for (i = 0; i < MAX_RADIX; i = i + 1) begin
        x_in[i] = 0;
    end
    
    // Reset pulse
    #20 rst_n = 1;
    #10;
    
    // Run tests
    run_all_tests();
    
    // Display test summary
    $display("\n==================================================");
    $display("Test Summary:");
    $display("  Total tests: %0d", test_num);
    $display("  Passed: %0d", pass_count);
    $display("  Failed: %0d", fail_count);
    
    if (fail_count == 0) begin
        $display("✓ All tests PASSED!");
    end else begin
        $display("✗ Some tests FAILED!");
    end
    $display("==================================================");
    
    #100 $finish;
end

// ============================================================================
// Waveform file generation
// ============================================================================
initial begin
    // VCD file for waveform viewing
    $dumpfile("waveform_correct.vcd");
    $dumpvars(0, tb_reconfigurable_winograd_butterfly_correct);
end

endmodule