// test_vivado_compat.v
// Vivado compatible pure Verilog testbench
`timescale 1ns / 1ps

module test_minimal();

// Parameters
parameter DATA_WIDTH = 32;
parameter MOD_WIDTH = 16;
parameter CLK_PERIOD = 10;  // 100MHz

// System signals
reg clk;
reg reset_n;

// Control signals
reg start_gen;
reg mode;
reg [1:0] precision;
reg [MOD_WIDTH-1:0] modulus;
reg [15:0] N;
reg [7:0] stage;
reg [7:0] index;

// Output signals
wire [DATA_WIDTH-1:0] tw_real;
wire [DATA_WIDTH-1:0] tw_imag;
wire gen_done;
wire gen_valid;
wire [15:0] gen_cycles;
wire [7:0] gen_latency;
wire parallel_active;
wire error;

// Clock generation
initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

// Reset generation
initial begin
    reset_n = 0;
    #100;
    reset_n = 1;
end

// Initialize inputs
initial begin
    start_gen = 0;
    mode = 0;
    precision = 2'b10;
    modulus = 12289;
    N = 256;
    stage = 0;
    index = 0;
end

// DUT instantiation
twiddle_dynamic_gen #(
    .DATA_WIDTH(DATA_WIDTH),
    .MODULUS_WIDTH(MOD_WIDTH),
    .MAX_MODULUS(12289),
    .PARALLEL_LEVEL(4),
    .PIPELINE_DEPTH(3),
    .Q_FORMAT(16)
) dut (
    .clk(clk),
    .reset_n(reset_n),
    .start_gen(start_gen),
    .mode(mode),
    .precision(precision),
    .modulus(modulus),
    .N(N),
    .stage(stage),
    .index(index),
    .twiddle_real(tw_real),
    .twiddle_imag(tw_imag),
    .gen_done(gen_done),
    .gen_valid(gen_valid),
    .gen_cycles(gen_cycles),
    .gen_latency(gen_latency),
    .parallel_active(parallel_active),
    .error(error)
);

// Main test sequence
initial begin
    // Wait for reset completion
    wait(reset_n == 1);
    #100;
    
    $display("=== Vivado Compatible Test Start ===");
    $display("Time: %t", $time);
    
    // Test 1: Basic generation
    $display("Test 1: Generate basic twiddle factor");
    start_gen = 1;
    @(posedge clk);
    start_gen = 0;
    
    wait(gen_done == 1);
    $display("Generation complete, cycle count: %d", gen_cycles);
    $display("Result: real=%h (%d), imag=%h (%d)", 
             tw_real, tw_real, tw_imag, tw_imag);
    
    #100;
    
    // Test 2: Different index
    $display("Test 2: Generate with different index");
    index = 1;
    start_gen = 1;
    @(posedge clk);
    start_gen = 0;
    
    wait(gen_done == 1);
    $display("Result: real=%h, imag=%h", tw_real, tw_imag);
    
    #100;
    
    // Test 3: Different modulus (generalization verification)
    $display("Test 3: Different modulus (generalization)");
    modulus = 7681;
    stage = 2;
    index = 5;
    start_gen = 1;
    @(posedge clk);
    start_gen = 0;
    
    wait(gen_done == 1);
    $display("Modulus: %d, Result: real=%h, imag=%h", modulus, tw_real, tw_imag);
    
    #100;
    
    // Test 4: Performance test
    $display("Test 4: Continuous generation test");
    mode = 1;  // Continuous mode
    start_gen = 1;
    
    for (integer i = 0; i < 5; i = i + 1) begin
        index = i;
        wait(gen_done == 1);
        $display("  [%0d] Latency: %d cycles", i, gen_latency);
        #10;
    end
    
    mode = 0;
    start_gen = 0;
    
    // Summary
    $display("=== Test Complete ===");
    $display("Error status: %b", error);
    
    if (error == 0)
        $display("PASS: Test passed");
    else
        $display("FAIL: Test failed");
    
    #100;
    $finish;
end

// Monitor signals
always @(posedge clk) begin
    if (gen_valid) begin
        $display("[%t] Valid output: real=%h, imag=%h", $time, tw_real, tw_imag);
    end
end

// Timeout detection
initial begin
    #(CLK_PERIOD * 10000);  // 100us timeout
    $display("ERROR: Timeout error");
    $finish;
end

endmodule