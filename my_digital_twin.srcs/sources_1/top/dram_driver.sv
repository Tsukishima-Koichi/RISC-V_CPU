`timescale 1ns / 1ps

module dram_driver(
    input  logic         clk                ,

    input  logic [17:0]  perip_addr         ,
    input  logic [31:0]  perip_wdata        ,
    input  logic [ 3:0]  perip_mask         , 
    input  logic         dram_wen           ,
    output logic [31:0]  perip_rdata        
);

    logic [15:0] dram_addr;
    logic [ 3:0] actual_wea; // 真正喂给 BRAM 的写使能

    // 内存地址只看字地址（去掉最低两位）
    assign dram_addr = perip_addr[17:2];

    // BRAM 原生支持字节写使能！
    // 只有当 dram_wen 有效时，才把 4位的 perip_mask 传给 BRAM，否则传 0
    assign actual_wea = dram_wen ? perip_mask : 4'b0000;

    // 例化生成的 BRAM IP
    BRAM_DRAM Mem_DRAM (
        .clka  (clk),
        .wea   (actual_wea),         // 4位掩码控制字节写入
        .addra (dram_addr),          // 16位字地址
        .dina  (perip_wdata),        // 32位写数据
        .douta (perip_rdata)         // 读数据直接输出
    );

endmodule












// `timescale 1ns / 1ps

// module dram_driver(
//     input  logic         clk                ,

//     input  logic [17:0]  perip_addr         ,
//     input  logic [31:0]  perip_wdata        ,
//     input  logic [ 3:0]  perip_mask         , // 已经改为4位
//     input  logic         dram_wen           ,
//     output logic [31:0]  perip_rdata        
// );
//     logic [15:0] dram_addr;
//     logic [31:0] dram_data, dram_rdata_raw;

//     // 内存地址只看字地址（去掉最低两位）
//     assign dram_addr = perip_addr[17:2];
    
//     // ==========================================
//     // 读逻辑：CPU 内部已完成读移位，这里直接透传物理内存原始数据！
//     // ==========================================
//     assign perip_rdata = dram_rdata_raw; 

//     DRAM Mem_DRAM (
//         .clk        (clk),
//         .a          (dram_addr),
//         .spo        (dram_rdata_raw),
//         .we         (dram_wen),
//         .d          (dram_data)
//     );

//     // ==========================================
//     // 写逻辑：优雅的 Read-Modify-Write (读改写)
//     // 完全听从 CPU 发出的 4位 Byte Enable，CPU 让我改哪个字节，我就改哪个字节
//     // ==========================================
//     always_comb begin
//         dram_data = dram_rdata_raw; // 第一步：默认取出老数据
        
//         if (dram_wen) begin         // 第二步：如果正在写入，根据掩码替换对应的字节
//             if (perip_mask[0]) dram_data[ 7: 0] = perip_wdata[ 7: 0];
//             if (perip_mask[1]) dram_data[15: 8] = perip_wdata[15: 8];
//             if (perip_mask[2]) dram_data[23:16] = perip_wdata[23:16];
//             if (perip_mask[3]) dram_data[31:24] = perip_wdata[31:24];
//         end
//     end

// endmodule