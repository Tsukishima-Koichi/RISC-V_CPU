`timescale 1ns / 1ps

module ALU#(
    parameter DATAWIDTH = 32	
)(
    input  logic [DATAWIDTH - 1:0]  A           ,
    input  logic [DATAWIDTH - 1:0]  B           ,
    input  logic [4:0]              ALUControl  , // 🌟 升级为 5 位
    output logic [DATAWIDTH - 1:0]  Result      
);
    // ==========================================
    // 🌟 M 扩展：乘法预计算 (生成 64 位中间结果)
    // ==========================================
    logic signed [63:0] mul_ss; // 有符号 * 有符号
    logic signed [63:0] mul_su; // 有符号 * 无符号
    logic        [63:0] mul_uu; // 无符号 * 无符号

    assign mul_ss = $signed(A) * $signed(B);
    // 对 B 补零强制作为无符号数，但整体放入有符号乘法器中计算
    assign mul_su = $signed(A) * $signed({1'b0, B}); 
    assign mul_uu = {32'b0, A} * {32'b0, B};

    // ==========================================
    // 🌟 M 扩展：除法异常判断
    // ==========================================
    logic is_div_zero, is_div_of;
    assign is_div_zero = (B == 32'b0);
    // 唯一的溢出条件：-2147483648 / -1
    assign is_div_of   = (A == 32'h8000_0000) && (B == 32'hFFFF_FFFF);

    // ==========================================
    // 核心计算网络
    // ==========================================
    always_comb begin
        case (ALUControl)
            // --- 基础 I/R 扩展 ---
            5'd0:  Result = A + B;
            5'd1:  Result = A - B;
            5'd2:  Result = A << B[4:0];
            5'd3:  Result = $signed(A) < $signed(B) ? 32'd1 : 32'd0;
            5'd4:  Result = A < B ? 32'd1 : 32'd0;
            5'd5:  Result = A ^ B;
            5'd6:  Result = A >> B[4:0];
            5'd7:  Result = $signed(A) >>> B[4:0];
            5'd8:  Result = A | B;
            5'd9:  Result = A & B;
            
            // --- M 扩展乘除法 ---
            5'd10: Result = mul_ss[31:0];  // MUL: 仅取低32位 (不管有无符号，低32位结果完全一致)
            5'd11: Result = mul_ss[63:32]; // MULH: 有符号高32位
            5'd12: Result = mul_su[63:32]; // MULHSU: 有符号×无符号 高32位
            5'd13: Result = mul_uu[63:32]; // MULHU: 无符号高32位
            
            5'd14: Result = is_div_zero ? 32'hFFFF_FFFF : (is_div_of ? A : $signed(A) / $signed(B)); // DIV
            5'd15: Result = is_div_zero ? 32'hFFFF_FFFF : (A / B);                                   // DIVU
            5'd16: Result = is_div_zero ? A : (is_div_of ? 32'b0 : $signed(A) % $signed(B));         // REM
            5'd17: Result = is_div_zero ? A : (A % B);                                               // REMU

            default: Result = A + B;
        endcase
    end
endmodule