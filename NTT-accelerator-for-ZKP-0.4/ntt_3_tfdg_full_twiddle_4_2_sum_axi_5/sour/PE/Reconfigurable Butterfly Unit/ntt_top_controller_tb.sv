`timescale 1ns/1ps

module ntt_top_controller_tb;
    parameter MAX_WIDTH = 256;
    parameter MAX_RADIX = 16;
    parameter NUM_CORES = 8;
    parameter MAX_N = 8;

    reg clk, rst_n, start_ntt;
    reg [1:0] radix_mode;
    reg [7:0] log2_N;
    reg [MAX_WIDTH-1:0] data_in [0:MAX_N-1];
    reg [MAX_WIDTH-1:0] twiddle_full [0:MAX_N/2-1];
    reg [MAX_WIDTH-1:0] modulus, N_prime, R2_mod_N;
    wire [MAX_WIDTH-1:0] data_out [0:MAX_N-1];
    wire ntt_done, ntt_valid;

    ntt_top_controller #(
        .MAX_WIDTH(MAX_WIDTH),
        .MAX_RADIX(MAX_RADIX),
        .NUM_CORES(NUM_CORES),
        .MAX_N(MAX_N)
    ) dut (
        .clk(clk), .rst_n(rst_n), .start_ntt(start_ntt),
        .radix_mode(radix_mode), .log2_N(log2_N),
        .data_in(data_in),
        .twiddle_full(twiddle_full),
        .modulus(modulus), .N_prime(N_prime), .R2_mod_N(R2_mod_N),
        .data_out(data_out), .ntt_done(ntt_done), .ntt_valid(ntt_valid)
    );

    always #5 clk = ~clk;

    localparam [255:0] P = 256'h30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001;
    localparam [255:0] NP = 256'h73f82f1d0d8341b2e39a9828990623916586864b4c6911b3c2e1f593efffffff;
    localparam [255:0] R2 = 256'h0216d0b17f4e44a58c49833d53bb808553fe3ab1e35c59e31bb8e645ae216da7;

    localparam [255:0] M1 = 256'h0e0a77c19a07df2f666ea36f7879462e36fc76959f60cd29ac96341c4ffffffb;
    localparam [255:0] M2 = 256'h1c14ef83340fbe5eccdd46def0f28c5c6df8ed2b3ec19a53592c68389ffffff6;
    localparam [255:0] M3 = 256'h2a1f6744ce179d8e334bea4e696bd28aa4f563c0de22677d05c29c54effffff1;
    localparam [255:0] M4 = 256'h07c5909386eddc93e16a48076063c05bb3bdf20e03c9c4156e76dadd4fffffeb;
    localparam [255:0] M5 = 256'h15d0085520f5bbc347d8eb76d8dd0689eaba68a3a32a913f1b0d0ef99fffffe6;
    localparam [255:0] M6 = 256'h23da8016bafd9af2ae478ee651564cb821b6df39428b5e68c7a34315efffffe1;
    localparam [255:0] M7 = 256'h0180a96573d3d9f85c65ec9f484e3a89307f6d866832bb013057819e4fffffdb;
    localparam [255:0] M8 = 256'h0f8b21270ddbb927c2d4900ec0c780b7677be41c0793882adcedb5ba9fffffd6;

    integer i, timeout;

    initial begin
        clk = 0; rst_n = 0; start_ntt = 0;
        radix_mode = 2'b10; log2_N = 8'd3;
        modulus = P; N_prime = NP; R2_mod_N = R2;

        for (i = 0; i < MAX_N; i = i + 1) data_in[i] = 0;

        // 设置输入数据（Montgomery 形式 1_M..8_M）
        data_in[0] = M1; data_in[1] = M2; data_in[2] = M3; data_in[3] = M4;
        data_in[4] = M5; data_in[5] = M6; data_in[6] = M7; data_in[7] = M8;

        twiddle_full[0] = M1;
        twiddle_full[1] = 256'h24407ce73f9ad9a9d976fd2b5d9429f72d60c6ff83cb85bef8ad4ae2b5ad7c3f;
        twiddle_full[2] = 256'h2b377b3539c108cf8db1627974096c6e5f3f172cb14791207f753d979edcef8b;
        twiddle_full[3] = 256'h1dbb3113ae748ed27ad23dd6d1277a24b069b2a25389b19511da29b6125d6166;

        #20 rst_n = 1;
        #20;

        // 控制器会通过 S_LOAD_INIT 同步写端口自行加载 data_in 到 buf_a
        $display("TB: Data will be loaded by controller via S_LOAD_INIT");

        // 加载位反转表（寄存器数组，$readmemh 没问题）
        $readmemh("br_table_16.hex", dut.br_table);

        $display("====================================");
        $display("NTT Controller Testbench (BRAM)");
        $display("====================================");

        @(posedge clk); start_ntt = 1;
        @(posedge clk); start_ntt = 0;

        timeout = 0;
        while (!ntt_done && timeout < 10000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        if (timeout >= 10000) begin
            $display("TIMEOUT");
        end else begin
            $display("Completed in %0d cycles", timeout);
            for (i = 0; i < 8; i = i + 1)
                $display("  data_out[%0d] = 0x%064h", i, data_out[i]);
            $display("PASS (visual check)");
        end

        #200; $finish;
    end

endmodule
