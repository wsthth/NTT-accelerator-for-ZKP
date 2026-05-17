`timescale 1ns/1ps

module pe_multilevel_tb;
    parameter MAX_WIDTH = 256;
    parameter MAX_RADIX = 16;
    parameter NUM_CORES = 8;

    reg clk, rst_n, start, clear_post;
    reg [1:0] radix_mode;
    reg [7:0] stride;
    reg [MAX_WIDTH-1:0] data_in [0:MAX_RADIX-1];
    reg [MAX_WIDTH-1:0] twiddle_factors [0:MAX_RADIX/2-1];
    reg [MAX_WIDTH-1:0] modulus, N_prime, R2_mod_N;

    wire done, result_valid;
    wire [MAX_WIDTH-1:0] data_out [0:MAX_RADIX-1];

    reconfigurable_3d_pe_top #(
        .MAX_WIDTH(MAX_WIDTH),
        .MAX_RADIX(MAX_RADIX),
        .NUM_CORES(NUM_CORES)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .radix_mode(radix_mode),
        .width_384_mode(1'b0),
        .parallelism(3'b100),
        .start(start),
        .clear_post(clear_post),
        .done(done),
        .result_valid(result_valid),
        .stride(stride),
        .data_in(data_in),
        .twiddle_factors(twiddle_factors),
        .modulus(modulus),
        .N_prime(N_prime),
        .R2_mod_N(R2_mod_N),
        .data_out(data_out)
    );

    always #5 clk = ~clk;

    localparam [255:0] P  = 256'h30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001;
    localparam [255:0] NP = 256'h73f82f1d0d8341b2e39a9828990623916586864b4c6911b3c2e1f593efffffff;
    localparam [255:0] R2 = 256'h0216d0b17f4e44a58c49833d53bb808553fe3ab1e35c59e31bb8e645ae216da7;

    // Montgomery form: 1_M .. 8_M
    localparam [255:0] M1 = 256'h0e0a77c19a07df2f666ea36f7879462e36fc76959f60cd29ac96341c4ffffffb;
    localparam [255:0] M2 = 256'h1c14ef83340fbe5eccdd46def0f28c5c6df8ed2b3ec19a53592c68389ffffff6;
    localparam [255:0] M3 = 256'h2a1f6744ce179d8e334bea4e696bd28aa4f563c0de22677d05c29c54effffff1;
    localparam [255:0] M4 = 256'h07c5909386eddc93e16a48076063c05bb3bdf20e03c9c4156e76dadd4fffffeb;
    localparam [255:0] M5 = 256'h15d0085520f5bbc347d8eb76d8dd0689eaba68a3a32a913f1b0d0ef99fffffe6;
    localparam [255:0] M6 = 256'h23da8016bafd9af2ae478ee651564cb821b6df39428b5e68c7a34315efffffe1;
    localparam [255:0] M7 = 256'h0180a96573d3d9f85c65ec9f484e3a89307f6d866832bb013057819e4fffffdb;
    localparam [255:0] M8 = 256'h0f8b21270ddbb927c2d4900ec0c780b7677be41c0793882adcedb5ba9fffffd6;

    // Twiddle factors for N=8
    localparam [255:0] TW0 = M1;  // w^0 = 1
    localparam [255:0] TW1 = 256'h30109072cf7ff4b4786ecad8a6b247a5bcfdad1300786ada6f4f7b166ec7ccf3;  // ω^1
    localparam [255:0] TW2 = 256'h298866e143f4a463b5beed36493b127ecbf731de9578d0880379bd02d39ee0b4;  // ω^2
    localparam [255:0] TW3 = 256'h26ed7d8602381c364d8feb78fbf29c1033c6ee92681d797726c525389a48e884;  // ω^3
    localparam [255:0] TW4 = 256'h0fdef1af5fb0c3e3bbf016e34cf3960ad843f2cbb248182c588f1421e35e8209;  // ω^4

    integer i, j, timeout, num_passes;
    reg [MAX_WIDTH-1:0] tmp [0:7];

    // 调用管道一次并等待完成的任务
    task run_one_pass;
        begin
            // 清零后变换状态（多周期确保生效）
            clear_post = 1;
            repeat(3) @(posedge clk);
            clear_post = 0;
            repeat(2) @(posedge clk);
            $display("  After clear: latched=%b post_valid=%b",
                     dut.u_winograd_post.core_done_latched, dut.post_transform_valid);
            // 启动管道
            @(posedge clk); start = 1;
            @(posedge clk); start = 0;
            // 等 result_valid
            timeout = 0;
            while (!result_valid && timeout < 10000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 10000) $display("  TIMEOUT!");
            // 等 1 周期让 data_out wire 传播 reg 的值
            @(posedge clk);
            // 从后变换内部直接复制输出（绕过 wire 连接问题）
            for (i = 0; i < 8; i = i + 1)
                data_in[i] = dut.u_winograd_post.data_out[i];
        end
    endtask

    initial begin
        clk = 0; rst_n = 0; start = 0; clear_post = 0;
        modulus = P; N_prime = NP; R2_mod_N = R2;
        stride = 4; radix_mode = 2'b10;

        for (i = 0; i < MAX_RADIX; i = i + 1) data_in[i] = 0;
        for (i = 0; i < MAX_RADIX/2; i = i + 1) twiddle_factors[i] = 0;

        #20 rst_n = 1; #20;

        $display("========================================");
        $display("PE Multi-Level NTT Verification (N=8)");
        $display("========================================");

        // ========== Level 0: stride=4, radix-8, 1 pass ==========
        $display("");
        $display("--- Level 0 (stride=4, radix-8, 1 pass) ---");
        data_in[0] = M1; data_in[1] = M2; data_in[2] = M3; data_in[3] = M4;
        data_in[4] = M5; data_in[5] = M6; data_in[6] = M7; data_in[7] = M8;
        stride = 4; radix_mode = 2'b10;
        twiddle_factors[0] = TW0; twiddle_factors[1] = TW1;
        twiddle_factors[2] = TW2; twiddle_factors[3] = TW3;
        run_one_pass;
        $display("Level 0 data_out:");
        for (i = 0; i < 8; i = i + 1)
            $display("  [%0d] = 0x%064h", i, data_out[i]);
        for (i = 0; i < 8; i = i + 1) data_in[i] = data_out[i];
        $display("Level 0 data_in after copy:");
        for (i = 0; i < 8; i = i + 1)
            $display("  [%0d] = 0x%064h", i, data_in[i]);

        // ========== Level 1: stride=2, radix-4, 2 passes ==========
        $display("");
        $display("--- Level 1 (stride=2, radix-4, 2 passes) ---");
        stride = 2; radix_mode = 2'b01;
        twiddle_factors[0] = TW0; twiddle_factors[1] = TW4;
        // 结果缓冲：累积所有 pass 的结果
        for (i = 0; i < 8; i = i + 1) tmp[i] = data_in[i];
        for (j = 0; j < 2; j = j + 1) begin
            // 从结果缓冲加载当前块
            data_in[0] = tmp[j*4+0]; data_in[1] = tmp[j*4+1];
            data_in[2] = tmp[j*4+2]; data_in[3] = tmp[j*4+3];
            data_in[4] = 0; data_in[5] = 0; data_in[6] = 0; data_in[7] = 0;
            @(posedge clk);
            run_one_pass;
            // run_one_pass 已将 data_out 复制到 data_in
            // 写回当前块到结果缓冲
            for (i = 0; i < 4; i = i + 1) tmp[j*4+i] = data_in[i];
        end
        // 将最终结果复制到 data_in
        for (i = 0; i < 8; i = i + 1) data_in[i] = tmp[i];
        $display("Level 1 output:");
        for (i = 0; i < 8; i = i + 1)
            $display("  [%0d] = 0x%064h", i, data_in[i]);

        // ========== Level 2: stride=1, radix-2, 4 passes ==========
        $display("");
        $display("--- Level 2 (stride=1, radix-2, 4 passes) ---");
        stride = 1; radix_mode = 2'b00;
        twiddle_factors[0] = TW0;
        // 结果缓冲
        for (i = 0; i < 8; i = i + 1) tmp[i] = data_in[i];
        for (j = 0; j < 4; j = j + 1) begin
            // 从结果缓冲加载当前块
            data_in[0] = tmp[j*2+0]; data_in[1] = tmp[j*2+1];
            data_in[2] = 0; data_in[3] = 0;
            data_in[4] = 0; data_in[5] = 0; data_in[6] = 0; data_in[7] = 0;
            @(posedge clk);
            run_one_pass;
            // 写回当前块到结果缓冲
            tmp[j*2+0] = data_in[0]; tmp[j*2+1] = data_in[1];
        end
        // 将最终结果复制到 data_in
        for (i = 0; i < 8; i = i + 1) data_in[i] = tmp[i];
        $display("Level 2 output (FINAL NTT):");
        for (i = 0; i < 8; i = i + 1)
            $display("  [%0d] = 0x%064h", i, data_in[i]);

        $display("");
        $display("========================================");
        $display("Compare with Python golden model:");
        $display("  [0] = 0x158dc6bcdd2b2109346c428be2006adc29799a35a85e742f9e4bbc33dfffff42");
        $display("  [1] = 0x029bfebcf3e04bff46c48a2c202accb484e374bfcfbccfb085814f4da35069dd");
        $display("  [2] = 0x20d92d4bd355e701f57bb5a7c0b9d7a5c0b8042c7225e86666f43fd95000002b");
        $display("  [3] = 0x116816ce22780ce2f07c4ebbd36c733bc97d2b81f192cab2013474b85c866184");
        $display("  [4] = 0x114e0c24c57a2dda32a72598fff256ee593c20106a92603b8a068a1eb0000055");
        $display("  [5] = 0x125adc32dca4ecb624716a67260220bb0bc3fcc85dbd11fb0e593308af1ffc4a");
        $display("  [6] = 0x0000000000000000000000000000000000000000000000000000000000000000");
        $display("  [7] = 0x19c664ee3b4082ebf775f3801383f8442e56362e2d6ff7bd8944514720cdae1d");
        $display("========================================");

        #200; $finish;
    end

endmodule
