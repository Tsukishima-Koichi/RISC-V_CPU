`timescale 1ns / 1ps

module dram_driver(
    input  logic         clk                ,

    input  logic [17:0]  perip_addr         ,
    input  logic [31:0]  perip_wdata        ,
    input  logic [ 3:0]  perip_mask         , // 已经改为4位
    input  logic         dram_wen           ,
    output logic [31:0]  perip_rdata        
);
    logic [15:0] dram_addr;
    logic [31:0] dram_data, dram_rdata_raw;

    // 内存地址只看字地址（去掉最低两位）
    assign dram_addr = perip_addr[17:2];
    
    // ==========================================
    // 读逻辑：CPU 内部已完成读移位，这里直接透传物理内存原始数据！
    // ==========================================
    assign perip_rdata = dram_rdata_raw; 

    DRAM Mem_DRAM (
        .clk        (clk),
        .a          (dram_addr),
        .spo        (dram_rdata_raw),
        .we         (dram_wen),
        .d          (dram_data)
    );

    // ==========================================
    // 写逻辑：优雅的 Read-Modify-Write (读改写)
    // 完全听从 CPU 发出的 4位 Byte Enable，CPU 让我改哪个字节，我就改哪个字节
    // ==========================================
    always_comb begin
        dram_data = dram_rdata_raw; // 第一步：默认取出老数据
        
        if (dram_wen) begin         // 第二步：如果正在写入，根据掩码替换对应的字节
            if (perip_mask[0]) dram_data[ 7: 0] = perip_wdata[ 7: 0];
            if (perip_mask[1]) dram_data[15: 8] = perip_wdata[15: 8];
            if (perip_mask[2]) dram_data[23:16] = perip_wdata[23:16];
            if (perip_mask[3]) dram_data[31:24] = perip_wdata[31:24];
        end
    end

endmodule