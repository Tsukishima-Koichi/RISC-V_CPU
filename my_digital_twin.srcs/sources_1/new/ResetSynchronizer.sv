`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/04/15 21:20:25
// Design Name: 
// Module Name: ResetSynchronizer
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module ResetSynchronizer (
    input  logic clk,
    input  logic async_rst_in,  // 来自板子上的物理按键（通常需要先做消抖处理）
    output logic sync_rst_out   // 送给你 CPU 内部所有模块的复位信号
);
    logic rst_sync_reg1, rst_sync_reg2;

    always_ff @(posedge clk, posedge async_rst_in) begin
        if (async_rst_in) begin
            // 异步复位：按下按键，立刻生效
            rst_sync_reg1 <= 1'b1;
            rst_sync_reg2 <= 1'b1;
        end else begin
            // 同步释放：松开按键后，经过两个时钟周期的“过滤”，安全对齐到时钟沿
            rst_sync_reg1 <= 1'b0;
            rst_sync_reg2 <= rst_sync_reg1; 
        end
    end

    assign sync_rst_out = rst_sync_reg2;
endmodule
