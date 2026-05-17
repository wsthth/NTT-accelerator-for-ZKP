`timescale 1ns/1ps

// ============================================================================
// 最小测试台：直接测试 PE 管道单级计算（stride=4, radix-8）
// 排除控制器干扰，手动驱动 start/done
//
// 过滤说明（在 xsim 控制台中使用）：
//   BF_START  — 蝶形核 start 信号触发时打印
//   BF_DONE   — 蝶形核 done 信号拉高时打印
//   PE_TOP    — PE 顶层 Winograd 预变换/后变换调试输出
// 以上三类信息均由被测模块内部 $display 输出，本 TB 不做额外修改。
// ============================================================================

module pe_single_level_tb;

    parameter MAX_WIDTH  = 256;
    parameter MAX_RADIX  = 16;
    parameter NUM_CORES  = 8;

    // ---------- 时钟 / 复位 ----------
    reg clk, rst_n;
    always #5 clk = ~clk;   // 100 MHz

    // ---------- 配置信号 ----------
    reg [1:0]  radix_mode;
    reg        width_384_mode;
    reg [2:0]  parallelism;
    reg [7:0]  stride;
    reg        start;

    // ---------- 数据端口 ----------
    reg  [MAX_WIDTH-1:0] data_in       [0:MAX_RADIX-1];
    reg  [MAX_WIDTH-1:0] twiddle_factors [0:MAX_RADIX/2-1];
    reg  [MAX_WIDTH-1:0] modulus, N_prime, R2_mod_N;

    wire [MAX_WIDTH-1:0] data_out      [0:MAX_RADIX-1];
    wire done, result_valid;

    // ---------- DUT ----------
    reconfigurable_3d_pe_top #(
        .MAX_WIDTH (MAX_WIDTH),
        .MAX_RADIX (MAX_RADIX),
        .NUM_CORES (NUM_CORES)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .radix_mode       (radix_mode),
        .width_384_mode   (width_384_mode),
        .parallelism      (parallelism),
        .start            (start),
        .done             (done),
        .result_valid     (result_valid),
        .stride           (stride),
        .data_in          (data_in),
        .twiddle_factors  (twiddle_factors),
        .modulus          (modulus),
        .N_prime          (N_prime),
        .R2_mod_N         (R2_mod_N),
        .data_out         (data_out)
    );

    // ========================================================================
    // BN254 Montgomery 形式常量
    // ========================================================================
    localparam [255:0] P  = 256'h30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001;
    localparam [255:0] NP = 256'h73f82f1d0d8341b2e39a9828990623916586864b4c6911b3c2e1f593efffffff;
    localparam [255:0] R2 = 256'h0216d0b17f4e44a58c49833d53bb808553fe3ab1e35c59e31bb8e645ae216da7;

    localparam [255:0] M1 = 256'h0e0a77c19a07df2f666ea36f7879462e36fc76959f60cd29ac96341c4ffffffb; // 1_M
    localparam [255:0] M2 = 256'h1c14ef83340fbe5eccdd46def0f28c5c6df8ed2b3ec19a53592c68389ffffff6; // 2_M
    localparam [255:0] M3 = 256'h2a1f6744ce179d8e334bea4e696bd28aa4f563c0de22677d05c29c54effffff1; // 3_M
    localparam [255:0] M4 = 256'h07c5909386eddc93e16a48076063c05bb3bdf20e03c9c4156e76dadd4fffffeb; // 4_M
    localparam [255:0] M5 = 256'h15d0085520f5bbc347d8eb76d8dd0689eaba68a3a32a913f1b0d0ef99fffffe6; // 5_M
    localparam [255:0] M6 = 256'h23da8016bafd9af2ae478ee651564cb821b6df39428b5e68c7a34315efffffe1; // 6_M
    localparam [255:0] M7 = 256'h0180a96573d3d9f85c65ec9f484e3a89307f6d866832bb013057819e4fffffdb; // 7_M
    localparam [255:0] M8 = 256'h0f8b21270ddbb927c2d4900ec0c780b7677be41c0793882adcedb5ba9fffffd6; // 8_M

    localparam [255:0] TW0 = M1;                                                               // tw[0] = 1_M
    localparam [255:0] TW1 = 256'h24407ce73f9ad9a9d976fd2b5d9429f72d60c6ff83cb85bef8ad4ae2b5ad7c3f; // tw[1]
    localparam [255:0] TW2 = 256'h2b377b3539c108cf8db1627974096c6e5f3f172cb14791207f753d979edcef8b; // tw[2]
    localparam [255:0] TW3 = 256'h1dbb3113ae748ed27ad23dd6d1277a24b069b2a25389b19511da29b6125d6166; // tw[3]

    // ========================================================================
    // 测试激励
    // ========================================================================
    integer i, timeout;

    initial begin
        clk = 0; rst_n = 0; start = 0;
        width_384_mode = 1'b0;
        radix_mode     = 2'b10;          // radix-8
        parallelism    = 3'b100;         // 8 核全开
        stride         = 8'd4;           // 单级 stride=4

        modulus  = P;
        N_prime  = NP;
        R2_mod_N = R2;

        // 初始化 data_in (MAX_RADIX=16, 前8个有效)
        for (i = 0; i < MAX_RADIX; i = i + 1) data_in[i] = 256'd0;
        data_in[0] = M1;  // 1_M
        data_in[1] = M2;  // 2_M
        data_in[2] = M3;  // 3_M
        data_in[3] = M4;  // 4_M
        data_in[4] = M5;  // 5_M
        data_in[5] = M6;  // 6_M
        data_in[6] = M7;  // 7_M
        data_in[7] = M8;  // 8_M

        // 初始化 twiddle_factors (MAX_RADIX/2=8, 前4个有效)
        twiddle_factors[0] = TW0;
        twiddle_factors[1] = TW1;
        twiddle_factors[2] = TW2;
        twiddle_factors[3] = TW3;
        for (i = 4; i < MAX_RADIX/2; i = i + 1) twiddle_factors[i] = 256'd0;

        // ---- 复位 ----
        #20 rst_n = 1;
        #20;

        $display("====================================================");
        $display("PE Single-Level TB : stride=4, radix-8, N=8");
        $display("====================================================");
        $display("TB: data_in[0..7] = 1_M .. 8_M (Montgomery)");
        $display("TB: tw[0..3]      = {1_M, tw1, tw2, tw3}");
        $display("");

        // ---- 触发 start ----
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        // ---- 等待 result_valid ----
        timeout = 0;
        while (!result_valid && timeout < 10000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        if (timeout >= 10000) begin
            $display("TB: TIMEOUT — result_valid not asserted within 10000 cycles");
        end else begin
            $display("TB: result_valid asserted after %0d cycles", timeout);
            $display("");
            $display("---------- Output data_out[0..7] ----------");
            for (i = 0; i < 8; i = i + 1)
                $display("  data_out[%0d] = 0x%064h", i, data_out[i]);
            $display("-------------------------------------------");
            $display("TB: PASS (visual check)");
        end

        #200;
        $finish;
    end

endmodule
