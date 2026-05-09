// ============================================================================
// Montgomery Modular Multiplier for 256-bit NTT
// ============================================================================
// This module implements the Montgomery modular multiplication algorithm:
//   Result = (a * b * R^{-1}) mod N
// where R = 2^256 (for 256-bit modulus)
// ============================================================================

module montgomery_mul_256bit (
    input wire clk,
    input wire reset_n,
    input wire start,          // Start signal for multiplication
    input wire [255:0] a,      // Input a (in Montgomery domain)
    input wire [255:0] b,      // Input b (in Montgomery domain)
    input wire [255:0] n,      // Modulus N (prime number)
    input wire [255:0] np,     // Precomputed N' = -N^{-1} mod R
    
    output reg [255:0] result, // Output: (a * b * R^{-1}) mod N
    output reg done,           // Done signal
    output reg busy            // Busy signal
);

// ============================================================================
// Local Parameters and Variables
// ============================================================================
localparam IDLE = 2'b00;
localparam CALC = 2'b01;
localparam FINISH = 2'b10;

reg [1:0] state;
reg [8:0] counter;           // Counter for 256-bit iterations (0-255)
reg [511:0] s;               // 512-bit accumulator (S in algorithm)
reg [255:0] a_reg, b_reg, n_reg, np_reg;
reg [255:0] m;               // Intermediate value m
reg [511:0] t;               // Intermediate product

// ============================================================================
// Montgomery Multiplication Algorithm
// ============================================================================
// Algorithm: Montgomery Product
// Input: a, b, N, N' where N' = -N^{-1} mod R, R = 2^256
// Output: a * b * R^{-1} mod N
//
// Steps:
//   1. t = a * b
//   2. m = t[255:0] * N' mod R  (only low 256 bits needed)
//   3. u = (t + m * N) / R      (division by R is right shift by 256 bits)
//   4. if u >= N then u = u - N
// ============================================================================

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        state <= IDLE;
        counter <= 9'd0;
        s <= 512'd0;
        result <= 256'd0;
        done <= 1'b0;
        busy <= 1'b0;
        a_reg <= 256'd0;
        b_reg <= 256'd0;
        n_reg <= 256'd0;
        np_reg <= 256'd0;
        m <= 256'd0;
        t <= 512'd0;
    end
    else begin
        case (state)
            IDLE: begin
                done <= 1'b0;
                if (start) begin
                    state <= CALC;
                    busy <= 1'b1;
                    counter <= 9'd0;
                    
                    // Store inputs
                    a_reg <= a;
                    b_reg <= b;
                    n_reg <= n;
                    np_reg <= np;
                    
                    // Initialize accumulator
                    s <= 512'd0;
                end
            end
            
            CALC: begin
                if (counter == 9'd0) begin
                    // Step 1: Compute t = a * b (512-bit product)
                    t = a_reg * b_reg;  // 256x256 multiply to get 512-bit result
                    counter <= counter + 1;
                end
                else if (counter == 9'd1) begin
                    // Step 2: Compute m = t[255:0] * N' mod R
                    // Since R = 2^256, we only need low 256 bits of product
                    m = t[255:0] * np_reg;
                    counter <= counter + 1;
                end
                else if (counter == 9'd2) begin
                    // Step 3: Compute u = (t + m * N) / R
                    // First compute m * N
                    s = m * n_reg;  // m * N (512-bit product)
                    counter <= counter + 1;
                end
                else if (counter == 9'd3) begin
                    // Add t to m*N
                    s = s + t;
                    counter <= counter + 1;
                end
                else if (counter == 9'd4) begin
                    // Division by R (right shift 256 bits)
                    // This gives us u = (t + m*N) >> 256
                    s = s >> 256;
                    counter <= counter + 1;
                end
                else if (counter == 9'd5) begin
                    // Check if u >= N
                    if (s[255:0] >= n_reg) begin
                        // Step 4: if u >= N, subtract N
                        s[255:0] = s[255:0] - n_reg;
                    end
                    state <= FINISH;
                    counter <= 9'd0;
                end
            end
            
            FINISH: begin
                result <= s[255:0];
                done <= 1'b1;
                busy <= 1'b0;
                state <= IDLE;
            end
        endcase
    end
end

endmodule


// ============================================================================
// Alternative: Pipelined Montgomery Multiplier (Higher Performance)
// ============================================================================
module montgomery_mul_pipelined_256bit (
    input wire clk,
    input wire reset_n,
    input wire start,
    input wire [255:0] a,
    input wire [255:0] b,
    input wire [255:0] n,
    input wire [255:0] np,
    
    output wire [255:0] result,
    output wire done,
    output wire busy
);

// Pipeline stages
localparam STAGES = 6;  // Total pipeline stages

reg [255:0] stage0_a, stage0_b, stage0_n, stage0_np;
reg [511:0] stage0_t;
reg stage0_valid;

reg [255:0] stage1_m;
reg [511:0] stage1_t;
reg [255:0] stage1_n;
reg stage1_valid;

reg [511:0] stage2_mn;
reg [511:0] stage2_t;
reg stage2_valid;

reg [511:0] stage3_sum;
reg stage3_valid;

reg [255:0] stage4_u;
reg [255:0] stage4_n;
reg stage4_valid;

reg [255:0] stage5_result;
reg stage5_valid;

// Input stage
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        stage0_valid <= 1'b0;
        stage0_a <= 256'd0;
        stage0_b <= 256'd0;
        stage0_n <= 256'd0;
        stage0_np <= 256'd0;
        stage0_t <= 512'd0;
    end
    else if (start) begin
        stage0_valid <= 1'b1;
        stage0_a <= a;
        stage0_b <= b;
        stage0_n <= n;
        stage0_np <= np;
        stage0_t <= a * b;  // Compute a*b
    end
    else begin
        stage0_valid <= 1'b0;
    end
end

// Stage 1: Compute m = t[255:0] * np mod R
always @(posedge clk) begin
    stage1_valid <= stage0_valid;
    if (stage0_valid) begin
        stage1_m <= stage0_t[255:0] * stage0_np;  // m = (a*b mod R) * np mod R
        stage1_t <= stage0_t;
        stage1_n <= stage0_n;
    end
end

// Stage 2: Compute m * N
always @(posedge clk) begin
    stage2_valid <= stage1_valid;
    if (stage1_valid) begin
        stage2_mn <= stage1_m * stage1_n;  // m * N
        stage2_t <= stage1_t;
    end
end

// Stage 3: Compute t + m*N
always @(posedge clk) begin
    stage3_valid <= stage2_valid;
    if (stage2_valid) begin
        stage3_sum <= stage2_t + stage2_mn;  // t + m*N
    end
end

// Stage 4: Compute u = (t + m*N) / R (right shift by 256 bits)
always @(posedge clk) begin
    stage4_valid <= stage3_valid;
    if (stage3_valid) begin
        stage4_u <= stage3_sum >> 256;  // Division by R
        stage4_n <= stage1_n;  // Need N for comparison
    end
end

// Stage 5: Final reduction if u >= N
always @(posedge clk) begin
    stage5_valid <= stage4_valid;
    if (stage4_valid) begin
        if (stage4_u >= stage4_n) begin
            stage5_result <= stage4_u - stage4_n;
        end
        else begin
            stage5_result <= stage4_u;
        end
    end
end

assign result = stage5_result;
assign done = stage5_valid;
assign busy = |{stage0_valid, stage1_valid, stage2_valid, stage3_valid, stage4_valid};

endmodule


// ============================================================================
// Montgomery Domain Converter
// ============================================================================
// Converts numbers to/from Montgomery domain
module montgomery_converter_256bit (
    input wire clk,
    input wire reset_n,
    input wire start,
    input wire [255:0] x,        // Input number
    input wire [255:0] n,        // Modulus
    input wire [255:0] r_mod_n,  // R mod N (precomputed)
    input wire [255:0] r2_mod_n, // R^2 mod N (precomputed)
    input wire mode,             // 0: to Montgomery, 1: from Montgomery
    
    output reg [255:0] result,
    output reg done
);

// Instantiate Montgomery multiplier
montgomery_mul_pipelined_256bit mul_inst (
    .clk(clk),
    .reset_n(reset_n),
    .start(start),
    .a(x),
    .b(mode ? 256'd1 : r2_mod_n),  // For to Montgomery: x * R^2, for from: x * 1
    .n(n),
    .np(),  // np should be input from outside
    .result(result),
    .done(done),
    .busy()
);

// Note: np needs to be computed externally as: np = -N^{-1} mod R

endmodule


// ============================================================================
// Testbench for Montgomery Multiplier
// ============================================================================
`ifdef TESTBENCH
module tb_montgomery_mul_256bit;

reg clk;
reg reset_n;
reg start;
reg [255:0] a, b, n, np;
wire [255:0] result;
wire done, busy;

// Test modulus (NTT-friendly prime)
localparam [255:0] TEST_N = 256'hffffffff00000001000000000000000000000000ffffffffffffffffffffffff;
// Example: N' = -N^{-1} mod 2^256
localparam [255:0] TEST_NP = 256'hffffffff00000001000000000000000000000000ffffffffffffffffffffffff;

montgomery_mul_256bit dut (
    .clk(clk),
    .reset_n(reset_n),
    .start(start),
    .a(a),
    .b(b),
    .n(n),
    .np(np),
    .result(result),
    .done(done),
    .busy(busy)
);

// Clock generation
always #5 clk = ~clk;

initial begin
    // Initialize
    clk = 0;
    reset_n = 0;
    start = 0;
    a = 256'd0;
    b = 256'd0;
    n = TEST_N;
    np = TEST_NP;
    
    // Reset
    #20 reset_n = 1;
    #10;
    
    // Test case 1: Small numbers
    $display("Test 1: Small numbers");
    a = 256'd12345;
    b = 256'd67890;
    start = 1;
    #10 start = 0;
    
    wait(done);
    #10;
    $display("Result = %h", result);
    
    // Test case 2: Random numbers
    $display("\nTest 2: Random numbers");
    a = 256'h1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
    b = 256'hfedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321;
    start = 1;
    #10 start = 0;
    
    wait(done);
    #10;
    $display("Result = %h", result);
    
    // Test case 3: Edge case (a = N-1, b = N-1)
    $display("\nTest 3: Edge case");
    a = TEST_N - 1;
    b = TEST_N - 1;
    start = 1;
    #10 start = 0;
    
    wait(done);
    #10;
    $display("Result = %h", result);
    
    $finish;
end

endmodule
`endif


// ============================================================================
// Helper Function for Precomputation
// ============================================================================
// This module precomputes N' = -N^{-1} mod R
module precompute_np (
    input wire [255:0] n,    // Modulus N (must be odd)
    output wire [255:0] np   // N' = -N^{-1} mod 2^256
);

// Algorithm to compute np (Montgomery inverse):
// np = 1
// for i = 1 to 256:
//   if (np * n mod 2^i) != 1
//     np = np + 2^{i-1}

// In practice, this is computed in software or using
// extended Euclidean algorithm

assign np = 256'h0;  // Should be computed externally

endmodule