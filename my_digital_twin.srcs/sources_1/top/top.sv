`timescale 1ns / 1ps


module top(
    input  wire i_sys_clk_p         ,
    input  wire i_sys_clk_n         ,
    input  wire i_uart_rx           ,
    output wire o_uart_tx           ,

    output wire [31:0] virtual_led  ,
    output wire [39:0] virtual_seg
);

    wire w_clk_50Mhz, cpu_clk;
    wire w_clk_rst;

    wire [7:0] virtual_key;
    wire [63:0] virtual_sw;

    wire [7:0] rx_data;
    wire rx_ready;
    wire tx_start;
    wire [7:0] tx_data;
    wire tx_busy;

    pll pll_inst(
        .clk_in1_p(i_sys_clk_p),
        .clk_in1_n(i_sys_clk_n),
        .clk_out1(w_clk_50Mhz),
        .clk_out2(cpu_clk),
        .locked(w_clk_rst)
    );

    // ========================================================
    // 显式声明信号，并明确高/低电平有效版本
    // ========================================================
    wire safe_rst_50M_high; // 高电平有效版本
    wire safe_rst_n_50M;    // 低电平有效版本

    ResetSynchronizer sync_50M (
        .clk(w_clk_50Mhz),
        .async_rst_in(~w_clk_rst),        // locked为0时产生复位动作(1)
        .sync_rst_out(safe_rst_50M_high)  // 输出高电平有效的同步复位
    );
    // 翻转为低电平有效，喂给需要低电平复位的外设 (UART, Twin_Controller)
    assign safe_rst_n_50M = ~safe_rst_50M_high;
    // ========================================================
    // 为 CPU 时钟域生成安全的高电平有效复位 (rst)
    // ========================================================
    wire safe_cpu_rst;
    ResetSynchronizer sync_cpu (
        .clk(cpu_clk),
        .async_rst_in(~w_clk_rst), // locked为0时产生复位动作(1)
        .sync_rst_out(safe_cpu_rst) // 输出高电平有效的同步复位喂给CPU
    );
    // ========================================================

    uart #(
        .CLK_FREQ(50000000),
        .BAUD_RATE(9600)
    ) uart_inst(
        .clk(w_clk_50Mhz),
        .rst_n(safe_rst_n_50M),
        .rx(i_uart_rx),
        .rx_data(rx_data),
        .rx_ready(rx_ready),
        .tx(o_uart_tx),
        .tx_data(tx_data),
        .tx_start(tx_start),
        .tx_busy(tx_busy)
    );

    twin_controller twin_controller_inst(
        .clk(w_clk_50Mhz),
        .rst_n(safe_rst_n_50M),
        .rx_ready(rx_ready),
        .rx_data(rx_data),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx_busy(tx_busy),
        .sw(virtual_sw),
        .key(virtual_key),
        .seg(virtual_seg),
        .led(virtual_led)
    );

    student_top student_top_inst(
        .w_cpu_clk(cpu_clk),
        .w_cpu_rst(safe_cpu_rst),
        .w_cnt_clk(w_clk_50Mhz),
        .w_cnt_rst(safe_rst_50M_high),
        .virtual_key(virtual_key),
        .virtual_sw(virtual_sw),
        .virtual_led(virtual_led),
        .virtual_seg(virtual_seg)
    );

endmodule

