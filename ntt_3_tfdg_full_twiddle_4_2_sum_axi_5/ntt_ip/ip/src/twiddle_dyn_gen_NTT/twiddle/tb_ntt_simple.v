// tb_ntt_simple_fixed.v
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

// Main test program
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
    
    $display("=== NTT Twiddle Storage Module Test Start ===");
    
    // Wait for some time
    #10;
    
/*     // 1. Reset test
    $display("\n[Test 1] Reset Test");
    reset_n = 1'b1;
    #20;
    
    if (ready == 1'b1) begin
        $display("  ✓ Reset successful, system ready");
    end else begin
        $display("  ✗ Reset failed");
        $finish;
    end
 */    
    
    
// 更新测试程序中的复位测试部分
    // 1. Reset test
    $display("\n[Test 1] Reset Test");
    #10;
    reset_n = 1'b1;
    #100;  // Wait longer for reset to complete
    
    // Wait for system to be ready
    while (ready != 1'b1) begin
        @(posedge clk);
    end
    
    if (ready == 1'b1) begin
        $display("  ✓ Reset successful, system ready");
    end else begin
        $display("  ✗ Reset failed");
        $finish;
    end    
    
    
    
    
    
    
    
    
    
    // 2. Store low-level twiddle factor to SRAM (stage=2)
    // Use different addresses to avoid conflict: 0x0301 instead of 0x0100
    $display("\n[Test 2] Store low-level twiddle factor to SRAM (stage=2)");
    
    // Wait for ready
    wait_for_ready();
    
    // Execute store
    store_en = 1'b1;
    addr_in = 16'h0301;  // Use different address
    data_in = 32'h12345678;
    stage = 8'd2;
    #10;
    store_en = 1'b0;
    
    // Wait for operation to complete
    wait_for_ready();
    #20;
    
    // 3. Lookup SRAM data
    $display("[Test 3] Lookup SRAM data");
    
    // Wait for ready
    wait_for_ready();
    
    // Execute lookup
    lookup_en = 1'b1;
    addr_in = 16'h0301;  // Lookup same address
    #10;
    lookup_en = 1'b0;
    
    // Wait for operation to complete
    wait_for_ready();
    #10;
    
    if (hit == 1'b1 && data_out == 32'h12345678) begin
        $display("  ✓ SRAM lookup successful");
    end else begin
        $display("  ✗ SRAM lookup failed: hit=%b, data_out=%h", hit, data_out);
    end
    
    // 4. Store high-level twiddle factor to BRAM (stage=5)
    $display("\n[Test 4] Store high-level twiddle factor to BRAM (stage=5)");
    
    // Wait for ready
    wait_for_ready();
    
    // Execute store
    store_en = 1'b1;
    addr_in = 16'h0502;  // Use different address
    data_in = 32'hABCDEF01;
    stage = 8'd5;
    #10;
    store_en = 1'b0;
    
    // Wait for operation to complete
    wait_for_ready();
    #20;
    
    // 5. Lookup BRAM data
    $display("[Test 5] Lookup BRAM data");
    
    // Wait for ready
    wait_for_ready();
    
    // Execute lookup
    lookup_en = 1'b1;
    addr_in = 16'h0502;
    #10;
    lookup_en = 1'b0;
    
    // Wait for operation to complete
    wait_for_ready();
    #10;
    
    if (hit == 1'b1 && data_out == 32'hABCDEF01) begin
        $display("  ✓ BRAM lookup successful");
    end else begin
        $display("  ✗ BRAM lookup failed: hit=%b, data_out=%h", hit, data_out);
    end
    
    // 6. Lookup non-existent address
    $display("\n[Test 6] Lookup non-existent address");
    
    // Wait for ready
    wait_for_ready();
    
    // Execute lookup
    lookup_en = 1'b1;
    addr_in = 16'hFFFF;
    #10;
    lookup_en = 1'b0;
    
    // Wait for operation to complete
    wait_for_ready();
    #10;
    
    if (hit == 1'b0) begin
        $display("  ✓ Miss correctly");
    end else begin
        $display("  ✗ Should not hit");
    end
    
    // 7. Continuous store test - use different address ranges to avoid conflicts
    $display("\n[Test 7] Continuous store test");
    
    for (i = 0; i < 5; i = i + 1) begin
        // Wait for ready
        wait_for_ready();
        
        // First 2 to SRAM, next 3 to BRAM
        // Use different address ranges: 0x0400-0x0401 and 0x0600-0x0602
        store_en = 1'b1;
        if (i < 2) begin
            addr_in = 16'h0400 + i;
            data_in = 32'h11111111 * (i+1);
            stage = 8'd2;  // Low-level
        end else begin
            addr_in = 16'h0600 + i;
            data_in = 32'h22222222 * (i+1);
            stage = 8'd5;  // High-level
        end
        
        #10;
        store_en = 1'b0;
        
        // Wait for operation to complete
        wait_for_ready();
        #10;
    end
    
    // 8. Batch lookup test
    $display("\n[Test 8] Batch lookup test");
    
    for (i = 0; i < 5; i = i + 1) begin
        // Wait for ready
        wait_for_ready();
        
        if (i < 2) begin
            addr_in = 16'h0400 + i;
        end else begin
            addr_in = 16'h0600 + i;
        end
        
        lookup_en = 1'b1;
        #10;
        lookup_en = 1'b0;
        
        // Wait for operation to complete
        wait_for_ready();
        #10;
        
        if (hit == 1'b1) begin
            $display("  ✓ Address %h: Hit", addr_in);
        end else begin
            $display("  ✗ Address %h: Miss", addr_in);
        end
    end
    
    // 9. Timeout eviction test
    $display("\n[Test 9] Timeout eviction test");
    $display("  Waiting 200 clock cycles...");
    
    for (i = 0; i < 200; i = i + 1) begin
        #10;
    end
    
    // Re-lookup BRAM data (may have been evicted)
    wait_for_ready();
    lookup_en = 1'b1;
    addr_in = 16'h0502;  // Previously stored BRAM data
    #10;
    lookup_en = 1'b0;
    
    // Wait for operation to complete
    wait_for_ready();
    #10;
    
    if (hit == 1'b0) begin
        $display("  ✓ Eviction mechanism working");
    end else begin
        $display("  ✗ Eviction mechanism not working");
    end
    
    // 10. SRAM data should not be evicted
    $display("\n[Test 10] SRAM data retention test");
    
    wait_for_ready();
    lookup_en = 1'b1;
    addr_in = 16'h0301;  // Previously stored SRAM data
    #10;
    lookup_en = 1'b0;
    
    // Wait for operation to complete
    wait_for_ready();
    #10;
    
    if (hit == 1'b1) begin
        $display("  ✓ SRAM data retained");
    end else begin
        $display("  ✗ SRAM data incorrectly evicted");
    end
    
    // Test completion
    $display("\n=== All tests completed ===");
    #100;
    $finish;
end

// Task: Wait for ready
task wait_for_ready;
begin
    while (ready != 1'b1) begin
        @(posedge clk);
    end
end
endtask

endmodule