// ============================================================================
// Montgomery Domain Converter (Correct Implementation)
// ============================================================================
// This module converts numbers between normal and Montgomery domains
// ============================================================================

module montgomery_converter_256bit_correct (
    input wire clk,
    input wire reset_n,
    input wire start,
    input wire [255:0] x,         // Input number
    input wire [255:0] n,         // Modulus
    input wire [255:0] np,        // Precomputed N' = -N^{-1} mod R
    input wire [255:0] r_mod_n,   // R mod N (precomputed)
    input wire [255:0] r2_mod_n,  // R^2 mod N (precomputed)
    input wire mode,              // 0: to Montgomery, 1: from Montgomery
    
    output reg [255:0] result,    // Output result
    output reg done,              // Done signal
    output reg busy               // Busy signal
);

// ============================================================================
// Local Variables and States
// ============================================================================
reg [255:0] a_reg, b_reg;
reg conv_start;
wire conv_done;
wire [255:0] conv_result;

// FSM states
localparam IDLE = 2'b00;
localparam CONVERT_TO = 2'b01;
localparam CONVERT_FROM = 2'b10;
localparam FINISH = 2'b11;

reg [1:0] state;

/* // Instantiate Montgomery multiplier
montgomery_mul_pipelined_256bit mul_inst (
    .clk(clk),
    .reset_n(reset_n),
    .start(conv_start),
    .a(a_reg),
    .b(b_reg),
    .n(n),
    .np(np),
    .result(conv_result),
    .done(conv_done),
    .busy()
);
 */
 
// Instantiate Montgomery multiplier
montgomery_multiplier_256bit mul_inst(
    .clk(clk),
    .reset_n(reset_n),
    .start(conv_start),
    .a_mont(a_reg),
    .b_mont(b_reg),
    .N(n),
    .N_prime(np),
    .result_mont(conv_result),
    .done(conv_done)
);


// ============================================================================
// Control Logic
// ============================================================================
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        state <= IDLE;
        done <= 1'b0;
        busy <= 1'b0;
        conv_start <= 1'b0;
        result <= 256'd0;
    end
    else begin
        case (state)
            IDLE: begin
                done <= 1'b0;
                if (start) begin
                    busy <= 1'b1;
                    
                    if (mode == 1'b0) begin
                        // Convert TO Montgomery domain: result = x * R mod N
                        // Method 1: x * R mod N
                        // Since we have R mod N precomputed, we can do:
                        //   temp = montgomery_mul(x, R^2 mod N)
                        //   = x * R^2 * R^{-1} mod N = x * R mod N
                        state <= CONVERT_TO;
                        a_reg <= x;          // x (normal domain)
                        b_reg <= r2_mod_n;   // R^2 mod N
                    end
                    else begin
                        // Convert FROM Montgomery domain: result = x * R^{-1} mod N
                        // This is simply montgomery_mul(x, 1)
                        state <= CONVERT_FROM;
                        a_reg <= x;          // x (Montgomery domain)
                        b_reg <= 256'd1;     // Multiply by 1
                    end
                    
                    conv_start <= 1'b1;
                end
            end
            
            CONVERT_TO: begin
                conv_start <= 1'b0;
                if (conv_done) begin
                    // First step: x * R^2 * R^{-1} = x * R mod N
                    // We need one more step: convert x*R to proper Montgomery form
                    // Actually, x*R is already in Montgomery domain!
                    // Because Montgomery domain representation of y is: y*R mod N
                    result <= conv_result;   // This is x*R mod N
                    state <= FINISH;
                end
            end
            
            CONVERT_FROM: begin
                conv_start <= 1'b0;
                if (conv_done) begin
                    // x * 1 * R^{-1} mod N = x * R^{-1} mod N
                    result <= conv_result;
                    state <= FINISH;
                end
            end
            
            FINISH: begin
                done <= 1'b1;
                busy <= 1'b0;
                state <= IDLE;
            end
        endcase
    end
end

endmodule