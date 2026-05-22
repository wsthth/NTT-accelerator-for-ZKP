`timescale 1ns/1ps

// N=1024 Quick Verification: Only Level 0, first 4 passes
module pe_e2e_tb_n1024_quick;
    parameter MAX_WIDTH = 256;
    parameter MAX_RADIX = 16;
    parameter NUM_CORES = 8;

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

    // Twiddle factors (Montgomery form)
    localparam [255:0] TW0 = 256'h0e0a77c19a07df2f666ea36f7879462e36fc76959f60cd29ac96341c4ffffffb;
    localparam [255:0] TW1 = 256'h30109072cf7ff4b4786ecad8a6b247a5bcfdad1300786ada6f4f7b166ec7ccf3;
    localparam [255:0] TW2 = 256'h298866e143f4a463b5beed36493b127ecbf731de9578d0880379bd02d39ee0b4;
    localparam [255:0] TW3 = 256'h26ed7d8602381c364d8feb78fbf29c1033c6ee92681d797726c525389a48e884;

    // Data buffers
    reg [MAX_WIDTH-1:0] input_data [0:1023];
    reg [MAX_WIDTH-1:0] result_buf [0:7];
    reg [MAX_WIDTH-1:0] tmp_buf [0:1023];

    integer i, j, timeout, errors;
    reg pass;

    // Read input data
    initial begin
        $readmemh("ntt_input_1024.txt", input_data);
        $display("Loaded input data from ntt_input_1024.txt");
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
            @(posedge clk); start = 1;  // hold 2 cycles
            @(posedge clk); start = 0;
            timeout = 0;
            while (!result_valid && timeout < 5000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 5000) $display("TIMEOUT!");

            for (i = 0; i < num_elements; i = i + 1)
                result_buf[i] = data_out[i];
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
        $display("N=1024 Quick Verification (Level 0, 4 passes)");
        $display("========================================");

        // Copy input to temp buffer
        for (i = 0; i < 1024; i = i + 1)
            tmp_buf[i] = input_data[i];

        // Level 0: radix-8, stride=4
        $display("");
        $display("--- Level 0 (radix-8, stride=4) ---");
        radix_mode = 2'b10;
        stride = 4;
        twiddle_factors[0] = TW0;
        twiddle_factors[1] = TW1;
        twiddle_factors[2] = TW2;
        twiddle_factors[3] = TW3;

        errors = 0;

        // Pass 0: elements [0:7]
        $display("");
        $display("--- Pass 0 (elements [0:7]) ---");
        run_one_pass(0, 8);
        $display("RTL output:");
        for (i = 0; i < 8; i = i + 1)
            $display("  [%0d] = 0x%064h", i, result_buf[i]);

        // Compare with expected (from Python golden model)
        if (result_buf[0] !== 256'h23da8016bafd9af2ae478ee651564cb821b6df39428b5e68c7a34315efffffe1) begin
            $display("  MISMATCH [0]: RTL=0x%064h, EXP=0x23da8016bafd9af2ae478ee651564cb821b6df39428b5e68c7a34315efffffe1", result_buf[0]);
            errors = errors + 1;
        end
        if (result_buf[1] !== 256'h289ebddf5a43c395d6e5fdaf211d98017475f63a75efac7bd56b1ab6a0000016) begin
            $display("  MISMATCH [1]: RTL=0x%064h, EXP=0x289ebddf5a43c395d6e5fdaf211d98017475f63a75efac7bd56b1ab6a0000016", result_buf[1]);
            errors = errors + 1;
        end
        if (result_buf[2] !== 256'h1a1e7b82c9e5b99f4d9465abd018280feab389ea673b780a5dbd894798aecda2) begin
            $display("  MISMATCH [2]: RTL=0x%064h, EXP=0x1a1e7b82c9e5b99f4d9465abd018280feab389ea673b780a5dbd894798aecda2", result_buf[2]);
            errors = errors + 1;
        end
        if (result_buf[3] !== 256'h1e0b63839e39c31e4c26281211ccf0a8f13e506c1647bc9c549b4729a751324a) begin
            $display("  MISMATCH [3]: RTL=0x%064h, EXP=0x1e0b63839e39c31e4c26281211ccf0a8f13e506c1647bc9c549b4729a751324a", result_buf[3]);
            errors = errors + 1;
        end
        if (result_buf[4] !== 256'h2a8060bc629e5b4dd9a2c483610141d347804f241a1777cd86cb05f1195824d7) begin
            $display("  MISMATCH [4]: RTL=0x%064h, EXP=0x2a8060bc629e5b4dd9a2c483610141d347804f241a1777cd86cb05f1195824d7", result_buf[4]);
            errors = errors + 1;
        end
        if (result_buf[5] !== 256'h29be6dcd3990dfce8cf5101971d66342026a785da22d572c84ba32b8c6a7db0b) begin
            $display("  MISMATCH [5]: RTL=0x%064h, EXP=0x29be6dcd3990dfce8cf5101971d66342026a785da22d572c84ba32b8c6a7db0b", result_buf[5]);
            errors = errors + 1;
        end
        if (result_buf[6] !== 256'h1cd7a6125184fd4bfc08018836f08eae60bdf4ee6a5cec670d54432a82474405) begin
            $display("  MISMATCH [6]: RTL=0x%064h, EXP=0x1cd7a6125184fd4bfc08018836f08eae60bdf4ee6a5cec670d54432a82474405", result_buf[6]);
            errors = errors + 1;
        end
        if (result_buf[7] !== 256'h2317c9879d885c057f1cd43d0b584a662ef1d77616f00c55137b68240db8bbd2) begin
            $display("  MISMATCH [7]: RTL=0x%064h, EXP=0x2317c9879d885c057f1cd43d0b584a662ef1d77616f00c55137b68240db8bbd2", result_buf[7]);
            errors = errors + 1;
        end
        if (errors == 0)
            $display("  PASS");
        else
            $display("  FAIL (%0d errors)", errors);

        // Pass 1: elements [8:15]
        $display("");
        $display("--- Pass 1 (elements [8:15]) ---");
        run_one_pass(8, 8);
        $display("RTL output:");
        for (i = 0; i < 8; i = i + 1)
            $display("  [%0d] = 0x%064h", i, result_buf[i]);

        if (result_buf[0] !== 256'h128c73f1f5836d187ba0694d5163f5c9c87abf28d7f8fe2d3d9cb8f73fffff8c) begin
            $display("  MISMATCH [0]");
            errors = errors + 1;
        end
        if (result_buf[1] !== 256'h289ebddf5a43c395d6e5fdaf211d98017475f63a75efac7bd56b1ab6a0000016) begin
            $display("  MISMATCH [1]");
            errors = errors + 1;
        end
        if (result_buf[2] !== 256'h270baca94a34171d115d1ecbba67230bf87d945aa4c6d27e96176b162eed3508) begin
            $display("  MISMATCH [2]");
            errors = errors + 1;
        end
        if (result_buf[3] !== 256'h303474ab39a2d7f00e068f0fa90cf71bb26c0e33e7e3727dd61cd0d05112ca90) begin
            $display("  MISMATCH [3]");
            errors = errors + 1;
        end
        if (result_buf[4] !== 256'h032c45568692364587ec90905f969397cd167ff0ffa5ffae6076f722d64f2a45) begin
            $display("  MISMATCH [4]");
            errors = errors + 1;
        end
        if (result_buf[5] !== 256'h0f602e9b6ef136d2f3b3d8bcf1cd6231fb643f37d852fe7edd25c1d469b0d547) begin
            $display("  MISMATCH [5]");
            errors = errors + 1;
        end
        if (result_buf[6] !== 256'h11108e4548c63702212a05614cc3855b4d05f3a25eca2c52453d6b9e648e87f4) begin
            $display("  MISMATCH [6]");
            errors = errors + 1;
        end
        if (result_buf[7] !== 256'h1d90d52fe0ccf4752753aacaf592fccae96db8b1b7f06c2e518bb5917b71778e) begin
            $display("  MISMATCH [7]");
            errors = errors + 1;
        end
        if (errors == 0)
            $display("  PASS");
        else
            $display("  FAIL (%0d errors)", errors);

        // Pass 2: elements [16:23]
        $display("");
        $display("--- Pass 2 (elements [16:23]) ---");
        run_one_pass(16, 8);
        $display("RTL output:");
        for (i = 0; i < 8; i = i + 1)
            $display("  [%0d] = 0x%064h", i, result_buf[i]);

        if (result_buf[0] !== 256'h013e67cd30093f3e48f943b451719edb6f3e9f186d669df1b3962ed88fffff37) begin
            $display("  MISMATCH [0]");
            errors = errors + 1;
        end
        if (result_buf[1] !== 256'h289ebddf5a43c395d6e5fdaf211d98017475f63a75efac7bd56b1ab6a0000016) begin
            $display("  MISMATCH [1]");
            errors = errors + 1;
        end
        if (result_buf[2] !== 256'h03948f5ce950d4711cd592352334c5aade13b6826898bc618a8f5750d52b9c6d) begin
            $display("  MISMATCH [2]");
            errors = errors + 1;
        end
        if (result_buf[3] !== 256'h11f9375ff3da4c981796b056becba5314b65e3b33fc5b7ce13bc64e30ad462d5) begin
            $display("  MISMATCH [3]");
            errors = errors + 1;
        end
        if (result_buf[4] !== 256'h0c3c78638bb7b166ee86a253dfad3db97ae099065eedf8207e04dde883462fb4) begin
            $display("  MISMATCH [4]");
            errors = errors + 1;
        end
        if (result_buf[5] !== 256'h25663ddc85832e0112c2e716f345b97f1c91ee5a8832166279734683fcb9cf84) begin
            $display("  MISMATCH [5]");
            errors = errors + 1;
        end
        if (result_buf[6] !== 256'h05497678400770b8464c093a62967c08394df25653376c3d7d26941246d5cbe3) begin
            $display("  MISMATCH [6]");
            errors = errors + 1;
        end
        if (result_buf[7] !== 256'h1809e0d824118ce4cf8a8158dfcdaf2fa3e999ed58f0cc078f9c02fee92a334a) begin
            $display("  MISMATCH [7]");
            errors = errors + 1;
        end
        if (errors == 0)
            $display("  PASS");
        else
            $display("  FAIL (%0d errors)", errors);

        // Pass 3: elements [24:31]
        $display("");
        $display("--- Pass 3 (elements [24:31]) ---");
        run_one_pass(24, 8);
        $display("RTL output:");
        for (i = 0; i < 8; i = i + 1)
            $display("  [%0d] = 0x%064h", i, result_buf[i]);

        if (result_buf[0] !== 256'h2054aa1b4bc0b18dcea263d1d300a04a3e3667507c8dae476d719a4dcffffee3) begin
            $display("  MISMATCH [0]");
            errors = errors + 1;
        end
        if (result_buf[1] !== 256'h289ebddf5a43c395d6e5fdaf211d98017475f63a75efac7bd56b1ab6a0000016) begin
            $display("  MISMATCH [1]");
            errors = errors + 1;
        end
        if (result_buf[2] !== 256'h1081c083699f31eee09e4b550d83c0a6ebddc0f2a62416d5c2e9391f6b6a03d3) begin
            $display("  MISMATCH [2]");
            errors = errors + 1;
        end
        if (result_buf[3] !== 256'h242248878f436169d9771754560baba40c93a17b11616daf953dee89b495fb1b) begin
            $display("  MISMATCH [3]");
            errors = errors + 1;
        end
        if (result_buf[4] !== 256'h154cab7090dd2c885520b4175fc3e7db28aab21bbe35f0929b92c4ae303d3523) begin
            $display("  MISMATCH [4]");
            errors = errors + 1;
        end
        if (result_buf[5] !== 256'h0b07feaabae385057981afba733cb86f158bb534be57bdb4d1ded59f9fc2c9c0) begin
            $display("  MISMATCH [5]");
            errors = errors + 1;
        end
        if (result_buf[6] !== 256'h29e6ad1e187a4a9823be52c9f9eacb124dc9d952c15e1cb9f8f1b21a191d0fd3) begin
            $display("  MISMATCH [6]");
            errors = errors + 1;
        end
        if (result_buf[7] !== 256'h1282ec806756255477c157e6ca0861945e657b28f9f12be0cdac506c56e2ef06) begin
            $display("  MISMATCH [7]");
            errors = errors + 1;
        end
        if (errors == 0)
            $display("  PASS");
        else
            $display("  FAIL (%0d errors)", errors);

        // Summary
        $display("");
        $display("========================================");
        if (errors == 0)
            $display("ALL 4 PASSES PASSED!");
        else
            $display("TOTAL ERRORS: %0d", errors);
        $display("========================================");

        #200; $finish;
    end

endmodule
