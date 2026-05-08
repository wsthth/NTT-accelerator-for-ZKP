// simple_dual_port_ram.v
`timescale 1ns / 1ps

module simple_dual_port_ram #(
    parameter WIDTH = 32,
    parameter DEPTH = 64,
    parameter ADDR_WIDTH = 6
)(
    input                         clk,
    input                         we,
    input  [ADDR_WIDTH-1:0]       waddr,
    input  [ADDR_WIDTH-1:0]       raddr,
    input  [WIDTH-1:0]            din,
    output reg [WIDTH-1:0]        dout
);

// 内存数组
reg [WIDTH-1:0] mem [0:DEPTH-1];

// 同步写
always @(posedge clk) begin
    if (we) begin
        mem[waddr] <= din;
    end
end

// 同步读（1周期延迟）
always @(posedge clk) begin
    dout <= mem[raddr];
end

endmodule