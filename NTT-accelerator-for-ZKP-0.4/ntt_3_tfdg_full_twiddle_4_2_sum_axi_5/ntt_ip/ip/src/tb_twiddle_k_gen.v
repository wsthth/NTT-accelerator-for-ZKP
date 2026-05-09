// tb_twiddle_k_gen.v：k值生成模块的测试用例
module tb_twiddle_k_gen;

reg [1:0] ntt_round;
reg [3:0] branch_j;
reg [3:0] butterfly_idx;
wire [7:0] normalized_k;
reg         rst_n;

// 例化被测模块
twiddle_k_gen u_k_gen(
    .ntt_round(ntt_round),
    .branch_j(branch_j),
    .butterfly_idx(butterfly_idx),
    .normalized_k(normalized_k)
);

// 激励：复现Python中测试过的i/j/butterfly组合
initial begin
    rst_n = 0;
    #10 rst_n = 1;
    
    // 测试用例1：i=0, j=8, butterfly_idx=2（对应Python的测试值）
    ntt_round = 0;
    branch_j = 8;
    butterfly_idx = 2;
    #10;
    $display("测试用例1：k值=%d（Python中应为10）", normalized_k);
    
    // 测试用例2：i=1, j=15, butterfly_idx=15
    ntt_round = 1;
    branch_j = 15;
    butterfly_idx = 15;
    #10;
    $display("测试用例2：k值=%d（Python中应为31）", normalized_k);
    
    #10 $finish;
end

endmodule