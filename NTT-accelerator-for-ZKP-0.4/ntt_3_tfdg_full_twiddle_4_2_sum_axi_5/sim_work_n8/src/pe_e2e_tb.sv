`timescale 1ns/1ps

// 端到端 NTT 验证：直接喂数据给管道，逐级对比
module pe_e2e_tb;
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

    localparam [255:0] P  = 256'h30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001;
    localparam [255:0] NP = 256'h73f82f1d0d8341b2e39a9828990623916586864b4c6911b3c2e1f593efffffff;
    localparam [255:0] R2 = 256'h0216d0b17f4e44a58c49833d53bb808553fe3ab1e35c59e31bb8e645ae216da7;

    // Twiddle factors (correct Montgomery form)
    localparam [255:0] TW0 = 256'h0e0a77c19a07df2f666ea36f7879462e36fc76959f60cd29ac96341c4ffffffb;  // w^0
    localparam [255:0] TW1 = 256'h30109072cf7ff4b4786ecad8a6b247a5bcfdad1300786ada6f4f7b166ec7ccf3;  // w^1
    localparam [255:0] TW2 = 256'h298866e143f4a463b5beed36493b127ecbf731de9578d0880379bd02d39ee0b4;  // w^2
    localparam [255:0] TW3 = 256'h26ed7d8602381c364d8feb78fbf29c1033c6ee92681d797726c525389a48e884;  // w^3
    localparam [255:0] TW4 = 256'h0fdef1af5fb0c3e3bbf016e34cf3960ad843f2cbb248182c588f1421e35e8209;  // w^4

    // Python golden model expected outputs (Montgomery form)
    // Level 0: computed using DIT pipeline model with radix=8, stride=4
    localparam [255:0] L0_0 = 256'h23da8016bafd9af2ae478ee651564cb821b6df39428b5e68c7a34315efffffe1;
    localparam [255:0] L0_1 = 256'h289ebddf5a43c395d6e5fdaf211d98017475f63a75efac7bd56b1ab6a0000016;
    localparam [255:0] L0_2 = 256'h1a1e7b82c9e5b99f4d9465abd018280feab389ea673b780a5dbd894798aecda2;
    localparam [255:0] L0_3 = 256'h1e0b63839e39c31e4c26281211ccf0a8f13e506c1647bc9c549b4729a751324a;
    localparam [255:0] L0_4 = 256'h2a8060bc629e5b4dd9a2c483610141d347804f241a1777cd86cb05f1195824d7;
    localparam [255:0] L0_5 = 256'h29be6dcd3990dfce8cf5101971d66342026a785da22d572c84ba32b8c6a7db0b;
    localparam [255:0] L0_6 = 256'h1cd7a6125184fd4bfc08018836f08eae60bdf4ee6a5cec670d54432a82474405;
    localparam [255:0] L0_7 = 256'h2317c9879d885c057f1cd43d0b584a662ef1d77616f00c55137b68240db8bbd2;

    // Level 1 expected outputs after 2 passes (Montgomery form)
    // RTL output order: [L1_0, L1_1, L1_2, L1_3, L1_4, L1_5, L1_6, L1_7]
    // Values match Python DIT model output directly
    localparam [255:0] L1_0 = 256'h0d94ad26a3b1b468438baedb9fed1c6ae43680db300d65e1e17ed6c998aecd82;
    localparam [255:0] L1_1 = 256'h09bc0493f117e15360b3293a813e24a83703554edb4fe65e69e5b9ce5751323f;
    localparam [255:0] L1_2 = 256'h023de18225da1621fc12906ead95ceef41f14b106066d2ed0b5e5fdb5f5bddbd;
    localparam [255:0] L1_3 = 256'h1e9b4bc9ad7bd0dff9692539132408b67ec6b91c11bf15795b95dffdf0a4226e;
    localparam [255:0] L1_4 = 256'h16f3b85bd2f1b8701d5a805516707824800a5bca0abaf3a3503d5387ab9f68db;
    localparam [255:0] L1_5 = 256'h0da8baaa11195e01dd9ac2fb2a10b324e6c25a35afba8b667976c2c69710e0d2;
    localparam [255:0] L1_6 = 256'h05c4dc0dd1ad8648d302518582e25593b0016f21f83ed5089762b24d980e839b;
    localparam [255:0] L1_7 = 256'h1d53b119c042992a8e9788f6df4918932c9f9950d26268bf2e2fbd900541327a;

    // Final NTT expected outputs after Level 2 (Montgomery form)
    localparam [255:0] NTT_0 = 256'h1750b1ba94c995bba43ed816212b41131b39d62a0b5d4c404b649097efffffc1;
    localparam [255:0] NTT_1 = 256'h03d8a892b299d314e2d885a11eaef7c2ad332b8c54bd7f8377991cfb415d9b43;
    localparam [255:0] NTT_2 = 256'h20d92d4bd355e701f57bb5a7c0b9d7a5c0b8042c7225e86666f43fd95000002b;
    localparam [255:0] NTT_3 = 256'h1406e42b598fe56bbaf9b0ec1bf31e95eb5e7a3cc8612e04f3aa75715eb7bb50;
    localparam [255:0] NTT_4 = 256'h249c7305e40b1671faf5435040812b4966ccb5ffba757f09c9b4164e42b049ad;
    localparam [255:0] NTT_5 = 256'h094afdb1c1d85a6e3fbfbd59ec5fc4ff994801945b00683cd6c690c1148e8809;
    localparam [255:0] NTT_6 = 256'h23188d2791f01f736199da7c622b6e26dca10872caa13dc7c5926fdd9d4fb615;
    localparam [255:0] NTT_7 = 256'h18d57966f29c8d47fcbb0e45251a955dab95be199f95dcdaad14ea5182cd5122;

    integer i, j, timeout;
    reg [MAX_WIDTH-1:0] result_buf [0:7];
    reg [MAX_WIDTH-1:0] tmp_buf [0:7];  // 中间结果缓冲
    reg pass;

    // 调用管道一次
    task run_one_pass;
        integer dbg_cycle;
        begin
            @(posedge clk); start = 1;
            @(posedge clk); start = 1;  // 保持2个周期，确保pre_transform IDLE能采样到
            @(posedge clk); start = 0;
            // 等待 result_valid 或超时
            timeout = 0;
            while (!result_valid && timeout < 5000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 5000) begin
                $display("  TIMEOUT! core_done=%b post_st=%0d", dut.core_done, dut.u_winograd_post.state);
            end
            // 直接从后变换内部寄存器读取
            for (i = 0; i < 8; i = i + 1)
                result_buf[i] = dut.u_winograd_post.data_out[i];

            // Debug: show core state after pass
            $display("  [DBG] timeout=%0d core_done=%b latch=%b post_st=%0d",
                timeout, dut.core_done, dut.u_winograd_post.core_done_latched, dut.u_winograd_post.state);
        end
    endtask

    // 对比函数
    function check_level;
        input [255:0] expected_0;
        input [255:0] expected_1;
        input [255:0] expected_2;
        input [255:0] expected_3;
        input [255:0] expected_4;
        input [255:0] expected_5;
        input [255:0] expected_6;
        input [255:0] expected_7;
        reg match;
        begin
            match = (result_buf[0] == expected_0) && (result_buf[1] == expected_1) &&
                    (result_buf[2] == expected_2) && (result_buf[3] == expected_3) &&
                    (result_buf[4] == expected_4) && (result_buf[5] == expected_5) &&
                    (result_buf[6] == expected_6) && (result_buf[7] == expected_7);
            if (!match) begin
                $display("  MISMATCH!");
                for (integer k = 0; k < 8; k = k + 1) begin
                    $display("    [%0d] RTL=0x%064h", k, result_buf[k]);
                end
            end
            check_level = match;
        end
    endfunction

    initial begin
        clk = 0; rst_n = 0; start = 0;
        radix_mode = 2'b10; stride = 4;
        modulus = P; N_prime = NP; R2_mod_N = R2;
        for (i = 0; i < MAX_RADIX; i = i + 1) data_in[i] = 0;
        for (i = 0; i < MAX_RADIX/2; i = i + 1) twiddle_factors[i] = 0;

        #20 rst_n = 1; #20;

        $display("========================================");
        $display("End-to-End NTT Verification");
        $display("========================================");

        // ========== Level 0: stride=4, radix-8 ==========
        $display("");
        $display("--- Level 0 (stride=4) ---");
        data_in[0] = 256'h0e0a77c19a07df2f666ea36f7879462e36fc76959f60cd29ac96341c4ffffffb;
        data_in[1] = 256'h1c14ef83340fbe5eccdd46def0f28c5c6df8ed2b3ec19a53592c68389ffffff6;
        data_in[2] = 256'h2a1f6744ce179d8e334bea4e696bd28aa4f563c0de22677d05c29c54effffff1;
        data_in[3] = 256'h07c5909386eddc93e16a48076063c05bb3bdf20e03c9c4156e76dadd4fffffeb;
        data_in[4] = 256'h15d0085520f5bbc347d8eb76d8dd0689eaba68a3a32a913f1b0d0ef99fffffe6;
        data_in[5] = 256'h23da8016bafd9af2ae478ee651564cb821b6df39428b5e68c7a34315efffffe1;
        data_in[6] = 256'h0180a96573d3d9f85c65ec9f484e3a89307f6d866832bb013057819e4fffffdb;
        data_in[7] = 256'h0f8b21270ddbb927c2d4900ec0c780b7677be41c0793882adcedb5ba9fffffd6;
        stride = 4; radix_mode = 2'b10;
        twiddle_factors[0] = TW0; twiddle_factors[1] = TW1;
        twiddle_factors[2] = TW2; twiddle_factors[3] = TW3;
        run_one_pass;
        $display("Level 0 output:");
        for (i = 0; i < 8; i = i + 1)
            $display("  [%0d] = 0x%064h", i, result_buf[i]);
        pass = check_level(L0_0, L0_1, L0_2, L0_3, L0_4, L0_5, L0_6, L0_7);
        $display("Level 0: %s", pass ? "PASS" : "FAIL");

        // ========== Level 1: stride=2, radix-4, 2 passes ==========
        $display("");
        $display("--- Level 1 (stride=2, radix-4, 2 passes) ---");
        stride = 2; radix_mode = 2'b01;
        twiddle_factors[0] = TW0; twiddle_factors[1] = TW4;
        // 将 Level 0 结果保存到临时缓冲
        for (i = 0; i < 8; i = i + 1) tmp_buf[i] = result_buf[i];
        // Pass 0: 处理 [0,1,2,3]
        data_in[0] = tmp_buf[0]; data_in[1] = tmp_buf[1];
        data_in[2] = tmp_buf[2]; data_in[3] = tmp_buf[3];
        data_in[4] = 0; data_in[5] = 0; data_in[6] = 0; data_in[7] = 0;
        run_one_pass;
        // 将结果写回临时缓冲
        for (i = 0; i < 4; i = i + 1) tmp_buf[i] = result_buf[i];
        $display("Level 1 Pass 0 output:");
        for (i = 0; i < 4; i = i + 1)
            $display("  [%0d] = 0x%064h", i, tmp_buf[i]);
        // Pass 1: 处理 [4,5,6,7]
        data_in[0] = tmp_buf[4]; data_in[1] = tmp_buf[5];
        data_in[2] = tmp_buf[6]; data_in[3] = tmp_buf[7];
        data_in[4] = 0; data_in[5] = 0; data_in[6] = 0; data_in[7] = 0;
        run_one_pass;
        // 将结果写回临时缓冲
        for (i = 0; i < 4; i = i + 1) tmp_buf[i+4] = result_buf[i];
        $display("Level 1 Pass 1 output:");
        for (i = 4; i < 8; i = i + 1)
            $display("  [%0d] = 0x%064h", i, tmp_buf[i]);
        // 复制到 result_buf 用于验证
        for (i = 0; i < 8; i = i + 1) result_buf[i] = tmp_buf[i];
        pass = pass && check_level(L1_0, L1_1, L1_2, L1_3, L1_4, L1_5, L1_6, L1_7);
        $display("Level 1: %s", pass ? "PASS" : "FAIL");

        // ========== Level 2: stride=1, radix-2, 4 passes ==========
        $display("");
        $display("--- Level 2 (stride=1, radix-2, 4 passes) ---");
        stride = 1; radix_mode = 2'b00;
        twiddle_factors[0] = TW0;
        // Pass 0: 处理 [0,1]
        data_in[0] = tmp_buf[0]; data_in[1] = tmp_buf[1];
        data_in[2] = 0; data_in[3] = 0; data_in[4] = 0; data_in[5] = 0;
        data_in[6] = 0; data_in[7] = 0;
        run_one_pass;
        tmp_buf[0] = result_buf[0]; tmp_buf[1] = result_buf[1];
        // Pass 1: 处理 [2,3]
        data_in[0] = tmp_buf[2]; data_in[1] = tmp_buf[3];
        run_one_pass;
        tmp_buf[2] = result_buf[0]; tmp_buf[3] = result_buf[1];
        // Pass 2: 处理 [4,5]
        data_in[0] = tmp_buf[4]; data_in[1] = tmp_buf[5];
        run_one_pass;
        tmp_buf[4] = result_buf[0]; tmp_buf[5] = result_buf[1];
        // Pass 3: 处理 [6,7]
        data_in[0] = tmp_buf[6]; data_in[1] = tmp_buf[7];
        run_one_pass;
        tmp_buf[6] = result_buf[0]; tmp_buf[7] = result_buf[1];
        // 打印最终结果
        $display("Level 2 final output (NTT result):");
        for (i = 0; i < 8; i = i + 1)
            $display("  [%0d] = 0x%064h", i, tmp_buf[i]);
        // 复制到 result_buf 用于验证
        for (i = 0; i < 8; i = i + 1) result_buf[i] = tmp_buf[i];
        pass = pass && check_level(NTT_0, NTT_1, NTT_2, NTT_3, NTT_4, NTT_5, NTT_6, NTT_7);
        $display("Level 2: %s", pass ? "PASS" : "FAIL");

        $display("");
        $display("========================================");
        $display("Final NTT Result (Montgomery form):");
        for (i = 0; i < 8; i = i + 1)
            $display("  [%0d] = 0x%064h", i, result_buf[i]);
        $display("========================================");
        $display(pass ? "ALL TESTS PASSED" : "SOME TESTS FAILED");
        $display("========================================");

        #200; $finish;
    end

endmodule
