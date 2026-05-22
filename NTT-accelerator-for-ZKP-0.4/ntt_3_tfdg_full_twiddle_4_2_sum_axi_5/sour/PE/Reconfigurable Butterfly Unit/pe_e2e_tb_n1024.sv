`timescale 1ns/1ps

// N=1024 NTT verification testbench
// Supports loading data from .txt files
module pe_e2e_tb_n1024;
    parameter MAX_WIDTH = 256;
    parameter MAX_RADIX = 16;
    parameter NUM_CORES = 8;
    parameter MAX_N = 1024;

    reg clk, rst_n, start;
    reg [1:0] radix_mode;
    reg [9:0] stride;
    reg [MAX_WIDTH-1:0] data_in [0:MAX_RADIX-1];
    reg [MAX_WIDTH-1:0] twiddle_factors [0:MAX_RADIX/2-1];
    reg [MAX_WIDTH-1:0] modulus, N_prime, R2_mod_N;
    wire done, result_valid;
    wire [MAX_WIDTH-1:0] data_out [0:MAX_RADIX-1];

    reconfigurable_3d_pe_top #(
        .MAX_WIDTH(MAX_WIDTH), .MAX_RADIX(MAX_RADIX), .NUM_CORES(NUM_CORES)
    ) dut (
        .clk(clk), .rst_n(rst_n), .radix_mode(radix_mode),
        .width_384_mode(1'b0), .parallelism(3'b100),
        .start(start), .clear_post(1'b0),
        .done(done), .result_valid(result_valid),
        .stride(stride), .data_in(data_in), .twiddle_factors(twiddle_factors),
        .modulus(modulus), .N_prime(N_prime), .R2_mod_N(R2_mod_N),
        .data_out(data_out)
    );

    always #5 clk = ~clk;

    // BN254 parameters
    localparam [255:0] P  = 256'h30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001;
    localparam [255:0] NP = 256'h73f82f1d0d8341b2e39a9828990623916586864b4c6911b3c2e1f593efffffff;
    localparam [255:0] R2 = 256'h0216d0b17f4e44a58c49833d53bb808553fe3ab1e35c59e31bb8e645ae216da7;

    // Data buffers
    reg [MAX_WIDTH-1:0] input_data [0:MAX_N-1];
    reg [MAX_WIDTH-1:0] expected_output [0:MAX_N-1];
    reg [MAX_WIDTH-1:0] result_buf [0:MAX_N-1];
    reg [MAX_WIDTH-1:0] tmp_buf [0:MAX_N-1];

    integer i, j, timeout, errors;
    reg pass;

    // Read data from files
    initial begin
        $readmemh("ntt_input_1024.txt", input_data);
        $display("Loaded input data from ntt_input_1024.txt");
        
        $readmemh("ntt_expected_1024.txt", expected_output);
        $display("Loaded expected output from ntt_expected_1024.txt");
    end

    // Run one pass through pipeline
    task run_one_pass;
        input integer start_idx;
        input integer num_elements;
        begin
            for (i = 0; i < MAX_RADIX; i = i + 1) begin
                if (i < num_elements)
                    data_in[i] = tmp_buf[start_idx + i];
                else
                    data_in[i] = 0;
            end
            
            @(posedge clk); start = 1;
            @(posedge clk); start = 1;  // hold 2 cycles for pre_transform IDLE sampling
            @(posedge clk); start = 0;
            timeout = 0;
            while (!result_valid && timeout < 5000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 5000) $display("TIMEOUT!");
            
            for (i = 0; i < num_elements; i = i + 1)
                result_buf[start_idx + i] = data_out[i];
        end
    endtask

    initial begin
        clk = 0; rst_n = 0; start = 0;
        radix_mode = 2'b10; stride = 4;
        modulus = P; N_prime = NP; R2_mod_N = R2;
        for (i = 0; i < MAX_RADIX; i = i + 1) data_in[i] = 0;
        for (i = 0; i < MAX_RADIX/2; i = i + 1) twiddle_factors[i] = 0;

        #20 rst_n = 1; #20;

        $display("========================================");
        $display("N=1024 NTT Verification");
        $display("========================================");

        // Copy input to temp buffer
        for (i = 0; i < MAX_N; i = i + 1)
            tmp_buf[i] = input_data[i];

        // Level 0: radix-8
        $display("");
        $display("--- Level 0 (radix-8, stride=4) ---");
        radix_mode = 2'b10;
        stride = 4;
        twiddle_factors[0] = 256'h0e0a77c19a07df2f666ea36f7879462e36fc76959f60cd29ac96341c4ffffffb;
        twiddle_factors[1] = 256'h30109072cf7ff4b4786ecad8a6b247a5bcfdad1300786ada6f4f7b166ec7ccf3;
        twiddle_factors[2] = 256'h298866e143f4a463b5beed36493b127ecbf731de9578d0880379bd02d39ee0b4;
        twiddle_factors[3] = 256'h26ed7d8602381c364d8feb78fbf29c1033c6ee92681d797726c525389a48e884;
        
        for (i = 0; i < MAX_N; i = i + 8) begin
            run_one_pass(i, 8);
            for (j = 0; j < 8; j = j + 1)
                tmp_buf[i + j] = result_buf[i + j];
        end

        // Level 1: radix-4
        $display("");
        $display("--- Level 1 (radix-4, stride=2) ---");
        radix_mode = 2'b01;
        stride = 2;
        twiddle_factors[0] = 256'h0e0a77c19a07df2f666ea36f7879462e36fc76959f60cd29ac96341c4ffffffb;
        twiddle_factors[1] = 256'h0fdef1af5fb0c3e3bbf016e34cf3960ad843f2cbb248182c588f1421e35e8209;
        
        for (i = 0; i < MAX_N; i = i + 4) begin
            run_one_pass(i, 4);
            for (j = 0; j < 4; j = j + 1)
                tmp_buf[i + j] = result_buf[i + j];
        end

        // Level 2-9: radix-2
        for (j = 2; j < 10; j = j + 1) begin
            $display("");
            $display("--- Level %0d (radix-2, stride=1) ---", j);
            radix_mode = 2'b00;
            stride = 1;
            twiddle_factors[0] = 256'h0e0a77c19a07df2f666ea36f7879462e36fc76959f60cd29ac96341c4ffffffb;
            
            for (i = 0; i < MAX_N; i = i + 2) begin
                run_one_pass(i, 2);
                tmp_buf[i] = result_buf[i];
                tmp_buf[i+1] = result_buf[i+1];
            end
        end

        // Copy final result
        for (i = 0; i < MAX_N; i = i + 1)
            result_buf[i] = tmp_buf[i];

        // Verify
        $display("");
        $display("========================================");
        $display("Result Verification");
        $display("========================================");
        errors = 0;
        for (i = 0; i < MAX_N; i = i + 1) begin
            if (result_buf[i] !== expected_output[i]) begin
                errors = errors + 1;
                if (errors <= 5)
                    $display("MISMATCH at [%0d]: RTL=0x%064h, EXP=0x%064h", i, result_buf[i], expected_output[i]);
            end
        end

        if (errors == 0) begin
            $display("ALL %0d RESULTS MATCH!", MAX_N);
            $display("TEST PASSED");
        end else begin
            $display("TOTAL ERRORS: %0d / %0d", errors, MAX_N);
            $display("TEST FAILED");
        end

        $display("========================================");

        #200; $finish;
    end

endmodule