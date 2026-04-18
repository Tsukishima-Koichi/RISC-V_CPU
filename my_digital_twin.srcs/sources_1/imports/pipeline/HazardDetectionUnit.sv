`timescale 1ns / 1ps
`include "defines.sv"

module HazardDetectionUnit(
    // 来自 ID 阶段
    input  logic [4:0] id_rs1,
    input  logic [4:0] id_rs2,
    input  logic [6:0] id_opcode,
    
    // 来自 EX 阶段 (上一条指令)
    input  logic       ex_RegWen,
    input  logic [1:0] ex_WbSel, // 2'b10 表示 Load
    input  logic [4:0] ex_rd,
    
    // 来自 MEM 阶段 (上上一条指令)
    input  logic [1:0] mem_WbSel, // 2'b10 表示 Load
    input  logic [4:0] mem_rd,
    
    output logic       stall_IF,
    output logic       stall_ID,
    output logic       flush_ID_EX
);
    logic is_load_use;
    logic is_branch_hazard;
    logic rs1_read, rs2_read;
    logic id_is_branch;


    // 🌟 核心修复：判断当前指令是否真的需要读取 rs1 和 rs2
    always_comb begin
        // 是否读取 rs1？
        case (id_opcode)
            // R型, I型(含算术和Load), JALR, S型(Store), B型(Branch), CSR 都需要读 rs1
            `R_TYPE, `I_TYPE, `IL_TYPE, `IJ_TYPE, `S_TYPE, `B_TYPE, `CSR_TYPE: 
                rs1_read = 1'b1;
            default: 
                rs1_read = 1'b0; // LUI, AUIPC, JAL 不读 rs1
        endcase

        // 是否读取 rs2？
        case (id_opcode)
            // R型, S型(Store), B型(Branch) 需要读 rs2
            `R_TYPE, `S_TYPE, `B_TYPE: 
                rs2_read = 1'b1;
            default: 
                rs2_read = 1'b0; // I型(含Load/JALR), U型, J型等 不读 rs2
        endcase
    end

    assign id_is_branch = (id_opcode == `B_TYPE) || (id_opcode == `IJ_TYPE) || (id_opcode == `J_TYPE);

    // 1. 原本的 Load-Use 冒险 (针对非 Branch 指令)
    always_comb begin
        is_load_use = 1'b0;
        if (!id_is_branch && (ex_WbSel == 2'b10) && (ex_rd != 5'd0)) begin
            if ((rs1_read && (ex_rd == id_rs1)) || (rs2_read && (ex_rd == id_rs2))) begin
                is_load_use = 1'b1;
            end
        end
    end

    // 2. 新增：Branch 专属的超前冒险检测
    always_comb begin
        is_branch_hazard = 1'b0;
        if (id_is_branch) begin
            // 情况 A：Branch 依赖 EX 阶段的计算结果 (ALU 或 Load) -> 必须 Stall 等待它流向 MEM/WB
            if (ex_RegWen && (ex_rd != 5'd0) && ((rs1_read && ex_rd == id_rs1) || (rs2_read && ex_rd == id_rs2))) begin
                is_branch_hazard = 1'b1;
            end
            // 情况 B：Branch 依赖 MEM 阶段的 Load 结果 (因为你的 BRAM 有 1 拍延迟，数据要在 WB 才出) -> 必须 Stall
            else if ((mem_WbSel == 2'b10) && (mem_rd != 5'd0) && ((rs1_read && mem_rd == id_rs1) || (rs2_read && mem_rd == id_rs2))) begin
                is_branch_hazard = 1'b1;
            end
        end
    end

    // 综合 Stall 逻辑
    assign stall_IF    = is_load_use | is_branch_hazard;
    assign stall_ID    = is_load_use | is_branch_hazard;
    assign flush_ID_EX = is_load_use | is_branch_hazard;

endmodule
