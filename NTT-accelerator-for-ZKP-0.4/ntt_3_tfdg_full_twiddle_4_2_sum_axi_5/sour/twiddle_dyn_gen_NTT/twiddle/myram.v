// simple_dual_port_ram.v
`timescale 1ns / 1ps

module simple_dual_port_ram #(
    parameter WIDTH = 32,
    parameter DEPTH = 64,
    parameter ADDR_WIDTH = 6,
    parameter NAME = "RAM"
)(
    input                         clk,
    input                         we,
    input  [ADDR_WIDTH-1:0]       waddr,
    input  [ADDR_WIDTH-1:0]       raddr,
    input  [WIDTH-1:0]            din,
    output reg [WIDTH-1:0]        dout,

    // 测试用异步写端口（仅仿真）
    input                         tb_we,
    input  [ADDR_WIDTH-1:0]       tb_waddr,
    input  [WIDTH-1:0]            tb_din
);

// 内存数组
reg [WIDTH-1:0] mem [0:DEPTH-1];

// 同步写
always @(posedge clk) begin
    if (we) begin
        mem[waddr] <= din;
        $display("BRAM[%0s] WR: waddr=%0d din=0x%064h", NAME, waddr, din);
    end
end

// 测试用异步写（仅仿真）
always @(*) begin
    if (tb_we) begin
        mem[tb_waddr] = tb_din;
    end
end

// 同步读（1周期延迟）
always @(posedge clk) begin
    dout <= mem[raddr];
    $display("BRAM[%0s] RD: raddr=%0d mem[raddr]=0x%064h", NAME, raddr, mem[raddr]);
end

endmodule