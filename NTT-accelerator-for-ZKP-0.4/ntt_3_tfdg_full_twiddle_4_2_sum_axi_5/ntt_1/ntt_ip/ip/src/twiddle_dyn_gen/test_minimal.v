// test_simple_en.v
`timescale 1ns / 1ps

module test_minmal();

parameter CLK_PERIOD = 10;  // 100MHz

// System signals
reg clk;
reg reset_n;
reg start_gen;

// Minimal DUT connection
wire gen_done;
wire error;

// Clock generation
initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

// Basic reset sequence
initial begin
    reset_n = 0;
    start_gen = 0;
    #100;
    reset_n = 1;
    #100;
end

// DUT instance - with minimal connections
twiddle_dynamic_gen #(
    .DATA_WIDTH(32),
    .MODULUS_WIDTH(16),
    .MAX_MODULUS(12289),
    .PARALLEL_LEVEL(4),
    .PIPELINE_DEPTH(3),
    .Q_FORMAT(16)
) dut (
    .clk(clk),
    .reset_n(reset_n),
    .start_gen(start_gen),
    .mode(0),
    .precision(2'b10),
    .modulus(12289),
    .N(256),
    .stage(0),
    .index(0),
    .twiddle_real(),
    .twiddle_imag(),
    .gen_done(gen_done),
    .gen_valid(),
    .gen_cycles(),
    .gen_latency(),
    .parallel_active(),
    .error(error)
);

// Simple test sequence
initial begin
    wait(reset_n == 1);
    #100;
    
    $display("=== Simple Debug Test ===");
    $display("Time: %t", $time);
    $display("Sending start pulse...");
    
    // Send start pulse
    start_gen = 1;
    #10;
    @(posedge clk);
    start_gen = 0;
    
    // Monitor for 100 cycles
/*     repeat(100) begin
        @(posedge clk);
        $display("[%t] Cycle %0d: gen_done=%b, error=%b", $time, $time/10, gen_done, error);
    end
 */    
    if (gen_done)
        $display("PASS: gen_done asserted within 100 cycles");
    else
        $display("FAIL: gen_done not asserted within 100 cycles");
    
    $finish;
end

endmodule