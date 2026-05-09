// twiddle_k_gen.v：生成带位反转偏移的归一化k值（256点基-16 NTT）
module twiddle_k_gen #(
    parameter N = 256,          // NTT长度
    parameter BASE = 16,        // 基-16
    parameter BIT_WIDTH = 8     // k值位宽（0~255）
)(
    input  wire [1:0]  ntt_round,      // NTT轮次（0/1）
    input  wire [3:0]  branch_j,       // 蝶形内分支（1~15）
    input  wire [3:0]  butterfly_idx,  // 蝶形索引（0~15）
    output reg  [7:0]  normalized_k    // 归一化k值（0~255）
);

// 位反转偏移（模拟真实NTT地址映射，与Python的bit_rev_offset一致）
wire [3:0] bit_rev_offset;
assign bit_rev_offset = {butterfly_idx[0], butterfly_idx[1], butterfly_idx[2], butterfly_idx[3]};
    reg [15:0] raw_k;

// 组合逻辑生成k值（与Python公式一致：raw_k = 16*i + j + 位反转偏移）
always @(*) begin
    raw_k = BASE * ntt_round + branch_j + bit_rev_offset;
    normalized_k = raw_k % N;  // 归一化到0~255
end

endmodule