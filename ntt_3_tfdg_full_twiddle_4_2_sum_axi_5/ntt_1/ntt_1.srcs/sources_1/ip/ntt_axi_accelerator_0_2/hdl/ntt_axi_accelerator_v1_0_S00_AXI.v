`timescale 1 ns / 1 ps

module ntt_axi_accelerator_v1_0_S00_AXI #
(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 10
)
(
    // Global Clock
    input wire  S_AXI_ACLK,
    // Global Reset (Active LOW)
    input wire  S_AXI_ARESETN,

    // AXI Write Address Channel
    input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_AWADDR,
    input wire [2 : 0] S_AXI_AWPROT,
    input wire  S_AXI_AWVALID,
    output wire  S_AXI_AWREADY,

    // AXI Write Data Channel
    input wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_WDATA,
    input wire [(C_S_AXI_DATA_WIDTH/8)-1 : 0] S_AXI_WSTRB,
    input wire  S_AXI_WVALID,
    output wire  S_AXI_WREADY,

    // AXI Write Response Channel
    output wire [1 : 0] S_AXI_BRESP,
    output wire  S_AXI_BVALID,
    input wire  S_AXI_BREADY,

    // AXI Read Address Channel
    input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_ARADDR,
    input wire [2 : 0] S_AXI_ARPROT,
    input wire  S_AXI_ARVALID,
    output wire  S_AXI_ARREADY,

    // AXI Read Data Channel
    output wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_RDATA,
    output wire [1 : 0] S_AXI_RRESP,
    output wire  S_AXI_RVALID,
    input wire  S_AXI_RREADY,

    // ==================== 新增端口（连接顶层） ====================
    // 输出寄存器值（软件写，硬件读）
    output wire [31:0] slv_reg0_o,
    output wire [31:0] slv_reg2_o,
    output wire [31:0] slv_reg3_o,
    output wire [31:0] slv_reg4_o,
    output wire [31:0] slv_reg5_o,
    output wire [31:0] slv_reg6_o,
    output wire [31:0] slv_reg7_o,
    output wire [31:0] slv_reg8_o,
    output wire [31:0] slv_reg9_o,
    output wire [31:0] slv_reg10_o,
    output wire [31:0] slv_reg11_o,
    output wire [31:0] slv_reg12_o,
    output wire [31:0] slv_reg13_o,
    output wire [31:0] slv_reg14_o,

    // 状态输入（硬件写，软件可读）
    input  wire [31:0] status_in_i
);

// AXI4-Lite Internal Signals
reg [C_S_AXI_ADDR_WIDTH-1 : 0] axi_awaddr;
reg   axi_awready;
reg   axi_wready;
reg [1 : 0] axi_bresp;
reg   axi_bvalid;
reg [C_S_AXI_ADDR_WIDTH-1 : 0] axi_araddr;
reg   axi_arready;
reg [C_S_AXI_DATA_WIDTH-1 : 0] axi_rdata;
reg [1 : 0] axi_rresp;
reg   axi_rvalid;

// Local Parameters
localparam ADDR_LSB          = (C_S_AXI_DATA_WIDTH/32) + 1;
localparam OPT_MEM_ADDR_BITS = 7;    // 2^7 = 128 → 对应 256 个寄存器
localparam REG_COUNT         = 256;  // 寄存器数量

// ===================== 核心优化：用数组代替 256 个独立寄存器 =====================
reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg [0:REG_COUNT-1];
// ================================================================================

wire slv_reg_wren;
wire slv_reg_rden;
reg [C_S_AXI_DATA_WIDTH-1:0] reg_data_out;
integer byte_index;
reg aw_en;

// I/O Assignments
assign S_AXI_AWREADY = axi_awready;
assign S_AXI_WREADY  = axi_wready;
assign S_AXI_BRESP   = axi_bresp;
assign S_AXI_BVALID  = axi_bvalid;
assign S_AXI_ARREADY = axi_arready;
assign S_AXI_RDATA   = axi_rdata;
assign S_AXI_RRESP   = axi_rresp;
assign S_AXI_RVALID  = axi_rvalid;

// ==================== 输出端口赋值 ====================
assign slv_reg0_o  = slv_reg[0];
assign slv_reg2_o  = slv_reg[2];
assign slv_reg3_o  = slv_reg[3];
assign slv_reg4_o  = slv_reg[4];
assign slv_reg5_o  = slv_reg[5];
assign slv_reg6_o  = slv_reg[6];
assign slv_reg7_o  = slv_reg[7];
assign slv_reg8_o  = slv_reg[8];
assign slv_reg9_o  = slv_reg[9];
assign slv_reg10_o = slv_reg[10];
assign slv_reg11_o = slv_reg[11];
assign slv_reg12_o = slv_reg[12];
assign slv_reg13_o = slv_reg[13];
assign slv_reg14_o = slv_reg[14];

// Implement axi_awready
always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN) begin
        axi_awready <= 1'b0;
        aw_en <= 1'b1;
    end else begin
        if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en) begin
            axi_awready <= 1'b1;
            aw_en <= 1'b0;
        end else if (S_AXI_BREADY && axi_bvalid) begin
            aw_en <= 1'b1;
            axi_awready <= 1'b0;
        end else begin
            axi_awready <= 1'b0;
        end
    end
end

// Latch Write Address
always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN)
        axi_awaddr <= 0;
    else if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en)
        axi_awaddr <= S_AXI_AWADDR;
end

// Implement axi_wready
always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN)
        axi_wready <= 1'b0;
    else if (~axi_wready && S_AXI_WVALID && S_AXI_AWVALID && aw_en)
        axi_wready <= 1'b1;
    else
        axi_wready <= 1'b0;
end

// ===================== 写逻辑：自动索引 =====================
assign slv_reg_wren = axi_wready && S_AXI_WVALID && axi_awready && S_AXI_AWVALID;
wire [OPT_MEM_ADDR_BITS:0] wr_index = axi_awaddr[ADDR_LSB + OPT_MEM_ADDR_BITS : ADDR_LSB];

always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN) begin
        for (byte_index = 0; byte_index < REG_COUNT; byte_index = byte_index + 1)
            slv_reg[byte_index] <= 0;
    end else if (slv_reg_wren) begin
        for (byte_index = 0; byte_index < (C_S_AXI_DATA_WIDTH/8); byte_index = byte_index + 1) begin
            if (S_AXI_WSTRB[byte_index])
                slv_reg[wr_index][byte_index*8 +: 8] <= S_AXI_WDATA[byte_index*8 +: 8];
        end
    end
end
// ============================================================================

// Write Response
always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN) begin
        axi_bvalid <= 0;
        axi_bresp  <= 2'b00;
    end else if (axi_awready && S_AXI_AWVALID && ~axi_bvalid && axi_wready && S_AXI_WVALID) begin
        axi_bvalid <= 1'b1;
        axi_bresp  <= 2'b00;
    end else if (S_AXI_BREADY && axi_bvalid) begin
        axi_bvalid <= 1'b0;
    end
end

// Read Address Ready
always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN) begin
        axi_arready <= 1'b0;
        axi_araddr  <= 0;
    end else if (~axi_arready && S_AXI_ARVALID) begin
        axi_arready <= 1'b1;
        axi_araddr  <= S_AXI_ARADDR;
    end else begin
        axi_arready <= 1'b0;
    end
end

// Read Valid
always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN) begin
        axi_rvalid <= 0;
        axi_rresp  <= 0;
    end else if (axi_arready && S_AXI_ARVALID && ~axi_rvalid) begin
        axi_rvalid <= 1'b1;
        axi_rresp  <= 2'b00;
    end else if (axi_rvalid && S_AXI_RREADY) begin
        axi_rvalid <= 1'b0;
    end
end

// ===================== 读逻辑：自动索引，并映射状态寄存器 =====================
assign slv_reg_rden = axi_arready & S_AXI_ARVALID & ~axi_rvalid;
wire [OPT_MEM_ADDR_BITS:0] rd_index = axi_araddr[ADDR_LSB + OPT_MEM_ADDR_BITS : ADDR_LSB];

always @(*) begin
    if (rd_index == 1)          // 地址 1 作为状态寄存器（只读）
        reg_data_out = status_in_i;
    else
        reg_data_out = slv_reg[rd_index];
end
// ============================================================================

// Read Data Output
always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN)
        axi_rdata <= 0;
    else if (slv_reg_rden)
        axi_rdata <= reg_data_out;
end

endmodule