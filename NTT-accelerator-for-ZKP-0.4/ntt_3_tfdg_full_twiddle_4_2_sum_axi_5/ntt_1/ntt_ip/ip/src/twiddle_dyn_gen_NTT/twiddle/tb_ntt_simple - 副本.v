// tb_ntt_simple.v
`timescale 1ns / 1ps

module tb_ntt_simple;

// Clock and reset
reg clk;
reg reset_n;

// Interface signals
reg store_en;
reg lookup_en;
reg [15:0] addr_in;
reg [31:0] data_in;
wire [31:0] data_out;
wire hit;
wire ready;
reg [7:0] stage;

// Loop variable
integer i;

// Instantiate DUT
ntt_twiddle_storage dut (
    .clk(clk),
    .reset_n(reset_n),
    .store_en(store_en),
    .lookup_en(lookup_en),
    .addr_in(addr_in),
    .data_in(data_in),
    .data_out(data_out),
    .hit(hit),
    .ready(ready),
    .stage(stage)
);

// Clock generation - 100MHz
initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
end

// Main test procedure
initial begin
    // Initialize signals
    reset_n = 1'b0;
    store_en = 1'b0;
    lookup_en = 1'b0;
    addr_in = 16'b0;
    data_in = 32'b0;
    stage = 8'b0;
    
    // Generate waveform file
    $dumpfile("ntt_wave.vcd");
    $dumpvars(0, tb_ntt_simple);
    
    $display("=== NTT Twiddle Factor Storage Module Test Start ===");
    
    // Test 1: Reset
    $display("\n[Test 1] Reset Test");
    #10;
    reset_n = 1'b1;
    #20;
    
    // Wait for system ready
    wait(ready == 1'b1);
    
    if (ready == 1'b1) begin
        $display("  correct Reset successful, system ready");
    end else begin
        $display("  wrong Reset failed");
        $finish;
    end
    
    // Test 2: Store low-stage twiddle factor to SRAM (stage=2)
    $display("\n[Test 2] Store low-stage twiddle factor to SRAM (stage=2)");
    
    // Wait for ready
    wait(ready == 1'b1);
    
    // Execute store
    store_en = 1'b1;
    addr_in = 16'h0100;
    data_in = 32'h12345678;
    stage = 8'd2;
    #10;
    store_en = 1'b0;
    
    // Wait for operation completion
    wait(ready == 1'b1);
    #20;
    
    // Test 3: Lookup SRAM data
    $display("[Test 3] Lookup SRAM data");
    
    // Wait for ready
    wait(ready == 1'b1);
    
    // Execute lookup
    lookup_en = 1'b1;
    addr_in = 16'h0100;
    #10;
    lookup_en = 1'b0;
    
    // Wait for operation completion
    wait(ready == 1'b1);
    #10;
    
    if (hit == 1'b1 && data_out == 32'h12345678) begin
        $display("  correct SRAM lookup successful");
    end else begin
        $display("  wrong SRAM lookup failed: hit=%b, data_out=%h", hit, data_out);
    end
    
    // Test 4: Store high-stage twiddle factor to BRAM (stage=5)
    $display("\n[Test 4] Store high-stage twiddle factor to BRAM (stage=5)");
    
    // Wait for ready
    wait(ready == 1'b1);
    
    // Execute store
    store_en = 1'b1;
    addr_in = 16'h0200;
    data_in = 32'hABCDEF01;
    stage = 8'd5;
    #10;
    store_en = 1'b0;
    
    // Wait for operation completion
    wait(ready == 1'b1);
    #20;
    
    // Test 5: Lookup BRAM data
    $display("[Test 5] Lookup BRAM data");
    
    // Wait for ready
    wait(ready == 1'b1);
    
    // Execute lookup
    lookup_en = 1'b1;
    addr_in = 16'h0200;
    #10;
    lookup_en = 1'b0;
    
    // Wait for operation completion
    wait(ready == 1'b1);
    #10;
    
    if (hit == 1'b1 && data_out == 32'hABCDEF01) begin
        $display("  correct BRAM lookup successful");
    end else begin
        $display("  wrong BRAM lookup failed: hit=%b, data_out=%h", hit, data_out);
    end
    
    // Test 6: Lookup non-existent address
    $display("\n[Test 6] Lookup non-existent address");
    
    // Wait for ready
    wait(ready == 1'b1);
    
    // Execute lookup
    lookup_en = 1'b1;
    addr_in = 16'hFFFF;
    #10;
    lookup_en = 1'b0;
    
    // Wait for operation completion
    wait(ready == 1'b1);
    #10;
    
    if (hit == 1'b0) begin
        $display("  correct Miss correct");
    end else begin
        $display("  wrong Should not hit");
    end
    
    // Test 7: Continuous store test
    $display("\n[Test 7] Continuous store test");
    
    for (i = 0; i < 5; i = i + 1) begin
        // Wait for ready
        wait(ready == 1'b1);
        
        // First 2 to SRAM, next 3 to BRAM
        store_en = 1'b1;
        if (i < 2) begin
            addr_in = 16'h1000 + i;
            data_in = 32'h11111111 * (i+1);
            stage = 8'd1;  // Low-stage
        end else begin
            addr_in = 16'h2000 + i;
            data_in = 32'h22222222 * (i+1);
            stage = 8'd4;  // High-stage
        end
        
        #10;
        store_en = 1'b0;
        
        // Wait for operation completion
        wait(ready == 1'b1);
        #10;
    end
    
    // Test 8: Batch lookup test
    $display("\n[Test 8] Batch lookup test");
    
    for (i = 0; i < 5; i = i + 1) begin
        // Wait for ready
        wait(ready == 1'b1);
        
        if (i < 2) begin
            addr_in = 16'h1000 + i;
        end else begin
            addr_in = 16'h2000 + i;
        end
        
        lookup_en = 1'b1;
        #10;
        lookup_en = 1'b0;
        
        // Wait for operation completion
        wait(ready == 1'b1);
        #10;
        
        if (hit == 1'b1) begin
            $display("  correct Address %h: Hit", addr_in);
        end else begin
            $display("  wrong Address %h: Miss", addr_in);
        end
    end
    
    // Test 9: Timeout eviction test
    $display("\n[Test 9] Timeout eviction test");
    $display("  Waiting for 200 clock cycles...");
    
    for (i = 0; i < 200; i = i + 1) begin
        #10;
    end
    
    // Lookup BRAM data again (might be evicted)
    wait(ready == 1'b1);
    lookup_en = 1'b1;
    addr_in = 16'h0200;  // BRAM data stored earlier
    #10;
    lookup_en = 1'b0;
    
    // Wait for operation completion
    wait(ready == 1'b1);
    #10;
    
    if (hit == 1'b0) begin
        $display("  correct Eviction mechanism working");
    end else begin
        $display("  wrong Eviction mechanism not working");
    end
    
    // Test completion
    $display("\n=== All tests completed ===");
    #100;
    $finish;
end

endmodule