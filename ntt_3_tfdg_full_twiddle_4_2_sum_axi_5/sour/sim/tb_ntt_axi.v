`timescale 1ns / 1ps

module tb_ntt_axi;

reg  aclk = 1'b0;
reg  aresetn = 1'b0;

always #5 aclk = ~aclk;

wire [31:0] s00_axi_awaddr;
wire        s00_axi_awvalid;
wire        s00_axi_awready;

wire [31:0] s00_axi_wdata;
wire [3:0]  s00_axi_wstrb;
wire        s00_axi_wvalid;
wire        s00_axi_wready;

wire [1:0]  s00_axi_bresp;
wire        s00_axi_bvalid;
reg         s00_axi_bready;

wire [31:0] s00_axi_araddr;
wire        s00_axi_arvalid;
wire        s00_axi_arready;

wire [31:0] s00_axi_rdata;
wire [1:0]  s00_axi_rresp;
wire        s00_axi_rvalid;
reg         s00_axi_rready;

// ==================== 只加这两个信号 ====================
reg  [2:0]  s00_axi_awprot;
reg  [2:0]  s00_axi_arprot;
// =======================================================

reg [31:0] awaddr;
reg        awvalid;
reg [31:0] wdata;
reg [3:0]  wstrb;
reg        wvalid;
reg [31:0] araddr;
reg        arvalid;

assign s00_axi_awaddr  = awaddr;
assign s00_axi_awvalid = awvalid;
assign s00_axi_wdata   = wdata;
assign s00_axi_wstrb   = wstrb;
assign s00_axi_wvalid  = wvalid;
assign s00_axi_araddr  = araddr;
assign s00_axi_arvalid = arvalid;

ntt_axi_accelerator_0 u_ntt (
    .s00_axi_aclk    (aclk),
    .s00_axi_aresetn (aresetn),

    .s00_axi_awaddr  (s00_axi_awaddr),
    .s00_axi_awvalid (s00_axi_awvalid),
    .s00_axi_awready (s00_axi_awready),
    
    // ==================== 只加这两行 ====================
    .s00_axi_awprot  (s00_axi_awprot),
    .s00_axi_arprot  (s00_axi_arprot),
    // ===================================================

    .s00_axi_wdata   (s00_axi_wdata),
    .s00_axi_wstrb   (s00_axi_wstrb),
    .s00_axi_wvalid  (s00_axi_wvalid),
    .s00_axi_wready  (s00_axi_wready),

    .s00_axi_bresp   (s00_axi_bresp),
    .s00_axi_bvalid  (s00_axi_bvalid),
    .s00_axi_bready  (s00_axi_bready),

    .s00_axi_araddr  (s00_axi_araddr),
    .s00_axi_arvalid (s00_axi_arvalid),
    .s00_axi_arready (s00_axi_arready),

    .s00_axi_rdata   (s00_axi_rdata),
    .s00_axi_rresp   (s00_axi_rresp),
    .s00_axi_rvalid  (s00_axi_rvalid),
    .s00_axi_rready  (s00_axi_rready)
);

initial begin
    awaddr  = 32'h0;
    awvalid = 1'b0;
    wdata   = 32'h0;
    wstrb   = 4'h0;
    wvalid  = 1'b0;
    araddr  = 32'h0;
    arvalid = 1'b0;
    s00_axi_bready = 1'b1;
    s00_axi_rready = 1'b1;

    // ==================== 只加这两行 ====================
    s00_axi_awprot = 3'b000;
    s00_axi_arprot = 3'b000;
    // ===================================================

    aresetn = 1'b0;
    #20 aresetn = 1'b1;

    $display("=====================================");
    $display("        AXI Lite Test Started        ");
    $display("=====================================");

    axi_write(32'h00, 32'h12345678);
    #20;

    axi_read(32'h00);
    #20;

    $display("=====================================");
    $display("      Simulation Completed!          ");
    $display("=====================================");
    $stop;
end

task axi_write;
    input [31:0] addr;
    input [31:0] data;
    begin
        awaddr  = addr;
        awvalid = 1'b1;
        wdata   = data;
        wstrb   = 4'b1111;
        wvalid  = 1'b1;

        @(posedge aclk);
        while (!(s00_axi_awready && s00_axi_wready)) begin
            @(posedge aclk);
        end

        awvalid = 1'b0;
        wvalid  = 1'b0;

        while (!s00_axi_bvalid) begin
            @(posedge aclk);
        end

        $display("WRITE OK: ADDR=0x%08h, DATA=0x%08h, RESP=%b", addr, data, s00_axi_bresp);
    end
endtask

task axi_read;
    input [31:0] addr;
    begin
        araddr  = addr;
        arvalid = 1'b1;

        @(posedge aclk);
        while (!s00_axi_arready) begin
            @(posedge aclk);
        end

        arvalid = 1'b0;

        while (!s00_axi_rvalid) begin
            @(posedge aclk);
        end

        $display("READ  OK: ADDR=0x%08h, DATA=0x%08h, RESP=%b", addr, s00_axi_rdata, s00_axi_rresp);
    end
endtask

endmodule