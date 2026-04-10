`timescale 1ns / 1ps
`include "defines.sv"

module ACTL(
    input  logic [6:0] opcode,
    input  logic [2:0] funct3,
    input  logic [6:0] funct7,   // 🌟 接收完整的 funct7
    output logic [4:0] alu_ctrl  // 🌟 扩展到 5 位
);
    // 基础算术
    localparam ALU_ADD  = 5'd0;
    localparam ALU_SUB  = 5'd1;
    localparam ALU_SLL  = 5'd2;
    localparam ALU_SLT  = 5'd3;
    localparam ALU_SLTU = 5'd4;
    localparam ALU_XOR  = 5'd5;
    localparam ALU_SRL  = 5'd6;
    localparam ALU_SRA  = 5'd7;
    localparam ALU_OR   = 5'd8;
    localparam ALU_AND  = 5'd9;
    
    // 🌟 M 扩展乘除法
    localparam ALU_MUL    = 5'd10;
    localparam ALU_MULH   = 5'd11;
    localparam ALU_MULHSU = 5'd12;
    localparam ALU_MULHU  = 5'd13;
    localparam ALU_DIV    = 5'd14;
    localparam ALU_DIVU   = 5'd15;
    localparam ALU_REM    = 5'd16;
    localparam ALU_REMU   = 5'd17;

    always_comb begin
        alu_ctrl = ALU_ADD; // 默认加法
        
        // 🌟 识别 RV32M 扩展指令
        if (opcode == `R_TYPE && funct7 == 7'b000_0001) begin
            case(funct3)
                3'b000: alu_ctrl = ALU_MUL;
                3'b001: alu_ctrl = ALU_MULH;
                3'b010: alu_ctrl = ALU_MULHSU;
                3'b011: alu_ctrl = ALU_MULHU;
                3'b100: alu_ctrl = ALU_DIV;
                3'b101: alu_ctrl = ALU_DIVU;
                3'b110: alu_ctrl = ALU_REM;
                3'b111: alu_ctrl = ALU_REMU;
            endcase
        end 
        // 基础 R-Type 和 I-Type 算术
        else if (opcode == `R_TYPE || opcode == `I_TYPE) begin
            case (funct3)
                3'b000: begin
                    // funct7[5] 即指令的第 30 位
                    if (opcode == `R_TYPE && funct7[5]) alu_ctrl = ALU_SUB;
                    else alu_ctrl = ALU_ADD;
                end
                3'b001: alu_ctrl = ALU_SLL;
                3'b010: alu_ctrl = ALU_SLT;
                3'b011: alu_ctrl = ALU_SLTU;
                3'b100: alu_ctrl = ALU_XOR;
                3'b101: begin
                    if (funct7[5]) alu_ctrl = ALU_SRA;
                    else alu_ctrl = ALU_SRL;
                end
                3'b110: alu_ctrl = ALU_OR;
                3'b111: alu_ctrl = ALU_AND;
            endcase
        end
    end
endmodule