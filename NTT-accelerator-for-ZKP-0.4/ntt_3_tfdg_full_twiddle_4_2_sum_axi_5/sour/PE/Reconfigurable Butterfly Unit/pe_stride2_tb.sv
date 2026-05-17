`timescale 1ns/1ps

// 直接测试管道 stride=2，排除控制器/级联干扰
module pe_stride2_tb;
    parameter MAX_WIDTH = 256;
    parameter MAX_RADIX = 16;
    parameter NUM_CORES = 8;

    reg clk, rst_n, start;
    reg [1:0] radix_mode;
    reg [7:0] stride;
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
        .start(start), .done(done), .result_valid(result_valid),
        .stride(stride), .data_in(data_in), .twiddle_factors(twiddle_factors),
        .modulus(modulus), .N_prime(N_prime), .R2_mod_N(R2_mod_N),
        .data_out(data_out)
    );

    always #5 clk = ~clk;

    localparam [255:0] P  = 256'h30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001;
    localparam [255:0] NP = 256'h73f82f1d0d8341b2e39a9828990623916586864b4c6911b3c2e1f593efffffff;
    localparam [255:0] R2 = 256'h0216d0b17f4e44a58c49833d53bb808553fe3ab1e35c59e31bb8e645ae216da7;

    // Level 0 输出（Montgomery 形式）作为 Level 1 输入
    localparam [255:0] L0_0 = 256'h23da8016bafd9af2ae478ee651564cb821b6df39428b5e68c7a34315efffffe1;
    localparam [255:0] L0_1 = 256'h289ebddf5a43c395d6e5fdaf211d98017475f63a75efac7bd56b1ab6a0000016;
    localparam [255:0] L0_2 = 256'h03a254b04bb8b7894c15d9529ae4ce55b53a0dbdf4e789f6d9d25da53210e96b;
    localparam [255:0] L0_3 = 256'h04233be33b35250a95546eb4c57ef205fe83e4500ee23a1e94a47d381def1680;
    localparam [255:0] L0_4 = 256'h05e5a0953a037a1708f3b3a30b245f032643abfe63054b67a6c9946eb80a8cb7;
    localparam [255:0] L0_5 = 256'h1df4df8180fa20dba553db434631edb4fb73333adf86130120d9aea737f5732a;
    localparam [255:0] L0_6 = 256'h03a990f2949a32571e6ada2d6218d7af6e07fdb63f781de7a9de5caa32eb0b16;
    localparam [255:0] L0_7 = 256'h0be19034794186d0a469b5e15eaea907f973e665c81b6a43330f59106d14f4c0;

    localparam [255:0] TW0 = 256'h0e0a77c19a07df2f666ea36f7879462e36fc76959f60cd29ac96341c4ffffffb;
    localparam [255:0] TW2 = 256'h2b377b3539c108cf8db1627974096c6e5f3f172cb14791207f753d979edcef8b;

    integer i, timeout;

    initial begin
        clk = 0; rst_n = 0; start = 0;
        modulus = P; N_prime = NP; R2_mod_N = R2;
        stride = 2; radix_mode = 2'b01;
        for (i = 0; i < MAX_RADIX; i = i + 1) data_in[i] = 0;
        for (i = 0; i < MAX_RADIX/2; i = i + 1) twiddle_factors[i] = 0;

        #20 rst_n = 1; #20;

        $display("=== PE stride=2 direct test ===");
        // 加载 level 0 输出的前 4 个元素
        data_in[0] = L0_0; data_in[1] = L0_1;
        data_in[2] = L0_2; data_in[3] = L0_3;
        twiddle_factors[0] = TW0; twiddle_factors[1] = TW2;

        $display("Input: [0]=0x%064h [1]=0x%064h [2]=0x%064h [3]=0x%064h",
                 data_in[0], data_in[1], data_in[2], data_in[3]);

        @(posedge clk); start = 1;
        @(posedge clk); start = 0;

        timeout = 0;
        while (!result_valid && timeout < 10000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        if (timeout >= 10000)
            $display("TIMEOUT");
        else begin
            $display("Completed in %0d cycles", timeout);
            for (i = 0; i < 8; i = i + 1)
                $display("  data_out[%0d] = 0x%064h", i, data_out[i]);
        end

        #200; $finish;
    end
endmodule
