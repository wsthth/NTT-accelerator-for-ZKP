`timescale 1 ns / 1 ps

module ntt_axi_accelerator_v1_0 #
(
    // 用户自定义参数
    parameter MAX_WIDTH    = 128,
    parameter MAX_RADIX    = 16,
    parameter NUM_CORES    = 4,
    
    // Do not modify the parameters beyond this line
    parameter integer C_S00_AXI_DATA_WIDTH = 32,
    parameter integer C_S00_AXI_ADDR_WIDTH = 10
)
(
    // Users to add ports here

    // User ports ends
    // Do not modify the ports beyond this line

    // Ports of Axi Slave Bus Interface S00_AXI
    input wire  s00_axi_aclk,
    input wire  s00_axi_aresetn,
    input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_awaddr,
    input wire [2 : 0] s00_axi_awprot,
    input wire  s00_axi_awvalid,
    output wire s00_axi_awready,
    input wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_wdata,
    input wire [(C_S00_AXI_DATA_WIDTH/8)-1 : 0] s00_axi_wstrb,
    input wire  s00_axi_wvalid,
    output wire s00_axi_wready,
    output wire [1 : 0] s00_axi_bresp,
    output wire s00_axi_bvalid,
    input wire  s00_axi_bready,
    input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_araddr,
    input wire [2 : 0] s00_axi_arprot,
    input wire  s00_axi_arvalid,
    output wire s00_axi_arready,
    output wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_rdata,
    output wire [1 : 0] s00_axi_rresp,
    output wire s00_axi_rvalid,
    input wire  s00_axi_rready
);

// =========================================================================
//  定义 AXI 输出到顶层的控制/配置信号
// =========================================================================
wire [31:0] ctrl_reg0;
wire [31:0] cfg_reg2;
wire [31:0] mod_lo;
wire [31:0] mod_mid;
wire [31:0] mod_hi;
wire [31:0] mod_extra;
wire [31:0] np_lo;
wire [31:0] np_mid;
wire [31:0] np_hi;
wire [31:0] np_extra;
wire [31:0] r2_lo;
wire [31:0] r2_mid;
wire [31:0] r2_hi;
wire [31:0] r2_extra;

// 状态返回信号
reg  [31:0] status_reg;
wire        done;
wire        result_valid;

// =========================================================================
//  Vivado 自动生成的 AXI 接口实例化（修改后的版本已包含所需端口）
// =========================================================================
ntt_axi_accelerator_v1_0_S00_AXI # ( 
    .C_S_AXI_DATA_WIDTH(C_S00_AXI_DATA_WIDTH),
    .C_S_AXI_ADDR_WIDTH(C_S00_AXI_ADDR_WIDTH)
) ntt_axi_accelerator_v1_0_S00_AXI_inst (
    .S_AXI_ACLK         (s00_axi_aclk),
    .S_AXI_ARESETN      (s00_axi_aresetn),
    .S_AXI_AWADDR       (s00_axi_awaddr),
    .S_AXI_AWPROT       (s00_axi_awprot),
    .S_AXI_AWVALID      (s00_axi_awvalid),
    .S_AXI_AWREADY      (s00_axi_awready),
    .S_AXI_WDATA        (s00_axi_wdata),
    .S_AXI_WSTRB        (s00_axi_wstrb),
    .S_AXI_WVALID       (s00_axi_wvalid),
    .S_AXI_WREADY       (s00_axi_wready),
    .S_AXI_BRESP        (s00_axi_bresp),
    .S_AXI_BVALID       (s00_axi_bvalid),
    .S_AXI_BREADY       (s00_axi_bready),
    .S_AXI_ARADDR       (s00_axi_araddr),
    .S_AXI_ARPROT       (s00_axi_arprot),
    .S_AXI_ARVALID      (s00_axi_arvalid),
    .S_AXI_ARREADY      (s00_axi_arready),
    .S_AXI_RDATA        (s00_axi_rdata),
    .S_AXI_RRESP        (s00_axi_rresp),
    .S_AXI_RVALID       (s00_axi_rvalid),
    .S_AXI_RREADY       (s00_axi_rready),

    // 输出寄存器值（连接到顶层 wire）
    .slv_reg0_o         (ctrl_reg0),
    .slv_reg2_o         (cfg_reg2),
    .slv_reg3_o         (mod_lo),
    .slv_reg4_o         (mod_mid),
    .slv_reg5_o         (mod_hi),
    .slv_reg6_o         (mod_extra),
    .slv_reg7_o         (np_lo),
    .slv_reg8_o         (np_mid),
    .slv_reg9_o         (np_hi),
    .slv_reg10_o        (np_extra),
    .slv_reg11_o        (r2_lo),
    .slv_reg12_o        (r2_mid),
    .slv_reg13_o        (r2_hi),
    .slv_reg14_o        (r2_extra),
    
    // 状态输入（软件可通过读地址 1 获取）
    .status_in_i        (status_reg)
);

// =========================================================================
// ======================== 用户逻辑：NTT加速器 ============================
// =========================================================================

// 1. 解析控制信号
wire        start         = ctrl_reg0[0];
wire [1:0]  radix_mode    = cfg_reg2[1:0];
wire        width_384_mode= cfg_reg2[2];
wire [2:0]  parallelism   = cfg_reg2[5:3];

// 2. 拼接 128bit 模参数
wire [127:0] modulus      = {mod_extra, mod_hi, mod_mid, mod_lo};
wire [127:0] N_prime      = {np_extra,  np_hi,  np_mid,  np_lo};
wire [127:0] R2_mod_N     = {r2_extra,  r2_hi,  r2_mid,  r2_lo};

// 3. 例化 NTT 加速器（可重构三维 PE 顶层）
reconfigurable_3d_pe_top #(
    .MAX_WIDTH  (MAX_WIDTH),
    .MAX_RADIX  (MAX_RADIX),
    .NUM_CORES  (NUM_CORES)
) u_ntt_core (
    .clk            (s00_axi_aclk),
    .rst_n          (s00_axi_aresetn),
    
    .radix_mode     (radix_mode),
    .width_384_mode (width_384_mode),
    .parallelism    (parallelism),
    
    .start          (start),
    .done           (done),
    .result_valid   (result_valid),
    
    // 数据输入：实际使用时需连接到 DMA 或 BRAM 接口，此处先接 0
    .data_in_flat       (2048'b0),
    .twiddle_factors_flat(1024'b0),
    
    .modulus        (modulus),
    .N_prime        (N_prime),
    .R2_mod_N       (R2_mod_N),
    
    .data_out_flat  ()   // 输出数据，可根据需要连接到 AXI 读通道
);

// 4. 状态寄存器（打拍，无毛刺）
always @(posedge s00_axi_aclk or negedge s00_axi_aresetn) begin
    if(!s00_axi_aresetn)
        status_reg <= 32'd0;
    else
        status_reg <= {30'd0, result_valid, done};
end

endmodule