// simplified_mod_mult_fixed.v
`timescale 1ns / 1ps

module simplified_mod_mult #(
    parameter DATA_WIDTH = 32
)(
    input wire clk,
    input wire reset_n,
    input wire start,
    input wire [DATA_WIDTH-1:0] a_real,
    input wire [DATA_WIDTH-1:0] a_imag,
    input wire [DATA_WIDTH-1:0] b_real,
    input wire [DATA_WIDTH-1:0] b_imag,
    input wire [DATA_WIDTH-1:0] modulus,
    output reg [DATA_WIDTH-1:0] result_real,
    output reg [DATA_WIDTH-1:0] result_imag,
    output reg done
);

reg [2:0] count;
reg active;

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        result_real <= 0;
        result_imag <= 0;
        done <= 0;
        count <= 0;
        active <= 0;
        $display("[%t] simplified_mod_mult: Module reset", $time);
    end else begin
        // Default done to 0 except when we're asserting it
        done <= 0;
        
        if (start && !active) begin
            // Start a new multiplication
            active <= 1;
            count <= 0;
            $display("[%t] simplified_mod_mult: Multiplication started", $time);
            $display("  Inputs: a_real=%h, a_imag=%h, b_real=%h, b_imag=%h, modulus=%h", 
                     a_real, a_imag, b_real, b_imag, modulus);
        end
        
        if (active) begin
            count <= count + 1;
            
            if (count == 2) begin
                // After 3 cycles (count 0,1,2), produce result
                // Simple fixed result for simulation
                result_real <= a_real;  // Just pass through for simulation
                result_imag <= a_imag;
                done <= 1;  // Assert done for one cycle
                active <= 0;  // Reset active flag
                
                $display("[%t] simplified_mod_mult: Multiplication completed", $time);
                $display("  Result: real=%h, imag=%h", a_real, a_imag);
            end else begin
                $display("[%t] simplified_mod_mult: Cycle %d (active)", $time, count);
            end
        end
    end
end

endmodule