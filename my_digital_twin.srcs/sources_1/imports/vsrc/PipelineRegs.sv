`timescale 1ns / 1ps

// ==========================================
// 1. IF1/IF2 Pipeline Register (🌟 新增)
// ==========================================
module IF1_IF2_Reg #(parameter DATAWIDTH = 32)(
    input  logic clk, rst, flush, stall,
    input  logic [DATAWIDTH-1:0] if1_pc, 
    output logic [DATAWIDTH-1:0] if2_pc, 
    output logic                 if2_valid // 标识此指令没有被冲刷
);
    always_ff @(posedge clk) begin
        if (rst || flush) begin
            if2_pc    <= 0;
            if2_valid <= 1'b0;
        end else if (!stall) begin
            if2_pc    <= if1_pc;
            if2_valid <= 1'b1;
        end
    end
endmodule

// ==========================================
// 2. IF2/ID Pipeline Register (原 IF_ID_Reg 修改)
// ==========================================
module IF2_ID_Reg #(parameter DATAWIDTH = 32)(
    input  logic clk, rst, flush, stall,
    input  logic [DATAWIDTH-1:0] if2_pc, 
    input  logic [DATAWIDTH-1:0] if2_inst, // 新增：锁存取到的指令
    input  logic                 if2_valid,
    output logic [DATAWIDTH-1:0] id_pc, 
    output logic [DATAWIDTH-1:0] id_inst_raw,
    output logic                 id_valid 
);
    always_ff @(posedge clk) begin
        if (rst || flush) begin
            id_pc       <= 0;
            id_inst_raw <= 0;
            id_valid    <= 1'b0;
        end else if (!stall) begin
            id_pc       <= if2_pc;
            id_inst_raw <= if2_inst;
            id_valid    <= if2_valid;
        end
    end
endmodule

// ==========================================
// 3. ID/EX Pipeline Register
// ==========================================
module ID_EX_Reg #(parameter DATAWIDTH = 32)(
    input  logic clk, rst, flush, stall,
    
    // Data
    input  logic [DATAWIDTH-1:0] id_pc, id_rs1_data, id_rs2_data, id_imm, id_ret_pc,
    input  logic [4:0]           id_rd, id_rs1, id_rs2,
    
    // Control
    input  logic       id_RegWen, id_MemWen, id_IsBranch, id_AluSrcB,
    input  logic [1:0] id_JmpType, id_WbSel, id_AluSrcA,
    input  logic [3:0] id_alu_ctrl,
    input  logic [2:0] id_funct3,
    
    input  logic [1:0] id_forward_A, id_forward_B, // <--- 新增：接收预计算的前递信号
    input  logic [DATAWIDTH-1:0] id_branch_target, // <--- 新增：接收 ID 阶段算好的分支目标地址

    // CSR
    input  logic [11:0] id_csr_idx,
    input  logic        id_CsrWen, id_CsrImmSel, id_IsEcall, id_IsEbreak, id_IsMret,
    input  logic [1:0]  id_CsrOp,
    
    // Outputs
    output logic [DATAWIDTH-1:0] ex_pc, ex_rs1_data, ex_rs2_data, ex_imm, ex_ret_pc,
    output logic [4:0]           ex_rd, ex_rs1, ex_rs2,
    output logic       ex_RegWen, ex_MemWen, ex_IsBranch, ex_AluSrcB,
    output logic [1:0] ex_JmpType, ex_WbSel, ex_AluSrcA,
    output logic [3:0] ex_alu_ctrl,
    output logic [2:0] ex_funct3,
    
    output logic [1:0] ex_forward_A, ex_forward_B, // <--- 新增：输出给 EX 阶段
    output logic [DATAWIDTH-1:0] ex_branch_target, // <--- 新增：输出给 EX 阶段

    // CSR
    output logic [11:0] ex_csr_idx,
    output logic        ex_CsrWen, ex_CsrImmSel, ex_IsEcall, ex_IsEbreak, ex_IsMret,
    output logic [1:0]  ex_CsrOp
);
    always_ff @(posedge clk) begin
        if (rst || flush) begin
            {ex_pc, ex_rs1_data, ex_rs2_data, ex_imm, ex_ret_pc} <= 0;
            {ex_rd, ex_rs1, ex_rs2} <= 0;
            {ex_RegWen, ex_MemWen, ex_IsBranch, ex_AluSrcB} <= 0;
            {ex_JmpType, ex_WbSel, ex_AluSrcA} <= 0;
            ex_alu_ctrl <= 0;
            ex_funct3   <= 0;
            {ex_forward_A, ex_forward_B} <= 0; // <--- 新增：复位清零
            {ex_csr_idx, ex_CsrWen, ex_CsrImmSel, ex_IsEcall, ex_IsEbreak, ex_IsMret, ex_CsrOp} <= 0;
            ex_branch_target <= 0; // 冲刷时清零
        end else if (!stall) begin
            {ex_pc, ex_rs1_data, ex_rs2_data, ex_imm, ex_ret_pc} <= {id_pc, id_rs1_data, id_rs2_data, id_imm, id_ret_pc};
            {ex_rd, ex_rs1, ex_rs2} <= {id_rd, id_rs1, id_rs2};
            {ex_RegWen, ex_MemWen, ex_IsBranch, ex_AluSrcB} <= {id_RegWen, id_MemWen, id_IsBranch, id_AluSrcB};
            {ex_JmpType, ex_WbSel, ex_AluSrcA} <= {id_JmpType, id_WbSel, id_AluSrcA};
            ex_alu_ctrl <= id_alu_ctrl;
            ex_funct3   <= id_funct3;
            {ex_forward_A, ex_forward_B} <= {id_forward_A, id_forward_B}; // <--- 新增：流水传递
            {ex_csr_idx, ex_CsrWen, ex_CsrImmSel, ex_IsEcall, ex_IsEbreak, ex_IsMret, ex_CsrOp} <=
                {id_csr_idx, id_CsrWen, id_CsrImmSel, id_IsEcall, id_IsEbreak, id_IsMret, id_CsrOp};
            ex_branch_target <= id_branch_target; // 流水传递
        end
    end
endmodule

// ==========================================
// 4. EX/MEM1 Pipeline Register
// ==========================================
module EX_MEM1_Reg #(parameter DATAWIDTH = 32)(
    input  logic clk, rst, flush, stall,
    
    input  logic [DATAWIDTH-1:0] ex_alu_res, ex_rs2_data, ex_ret_pc, ex_agu_res, ex_csr_rdata,
    input  logic [4:0]           ex_rd,
    input  logic                 ex_RegWen, ex_MemWen,
    input  logic [1:0]           ex_WbSel,
    input  logic [2:0]           ex_funct3,
    
    output logic [DATAWIDTH-1:0] mem1_alu_res, mem1_rs2_data, mem1_ret_pc, mem1_agu_res, mem1_csr_rdata,
    output logic [4:0]           mem1_rd,
    output logic                 mem1_RegWen, mem1_MemWen,
    output logic [1:0]           mem1_WbSel,
    output logic [2:0]           mem1_funct3
);
    always_ff @(posedge clk) begin
        if (rst || flush) begin
            {mem1_alu_res, mem1_rs2_data, mem1_ret_pc, mem1_agu_res, mem1_csr_rdata} <= 0;
            mem1_rd <= 0;
            {mem1_RegWen, mem1_MemWen} <= 0;
            mem1_WbSel <= 0;
            mem1_funct3 <= 0;
        end else if (!stall) begin
            {mem1_alu_res, mem1_rs2_data, mem1_ret_pc, mem1_agu_res, mem1_csr_rdata} <= 
            {ex_alu_res,   ex_rs2_data,   ex_ret_pc,   ex_agu_res,   ex_csr_rdata};
            mem1_rd <= ex_rd;
            {mem1_RegWen, mem1_MemWen} <= {ex_RegWen, ex_MemWen};
            mem1_WbSel <= ex_WbSel;
            mem1_funct3 <= ex_funct3;
        end
    end
endmodule

// ==========================================
// 5. MEM1/MEM2 Pipeline Register (新增的第七级)
// ==========================================
module MEM1_MEM2_Reg #(parameter DATAWIDTH = 32)(
    input  logic clk, rst, flush, stall,
    // 注意：BRAM 写数据已经发出了，所以 MEM2 不需要 MemWen 和 rs2_data 了
    input  logic [DATAWIDTH-1:0] mem1_alu_res, mem1_agu_res, mem1_ret_pc, mem1_csr_rdata,
    input  logic [4:0]           mem1_rd,
    input  logic                 mem1_RegWen,
    input  logic [1:0]           mem1_WbSel,
    input  logic [2:0]           mem1_funct3,

    output logic [DATAWIDTH-1:0] mem2_alu_res, mem2_agu_res, mem2_ret_pc, mem2_csr_rdata,
    output logic [4:0]           mem2_rd,
    output logic                 mem2_RegWen,
    output logic [1:0]           mem2_WbSel,
    output logic [2:0]           mem2_funct3
);
    always_ff @(posedge clk) begin
        if (rst || flush) begin
            {mem2_alu_res, mem2_agu_res, mem2_ret_pc, mem2_csr_rdata} <= 0;
            mem2_rd <= 0; mem2_RegWen <= 0; mem2_WbSel <= 0; mem2_funct3 <= 0;
        end else if (!stall) begin
            {mem2_alu_res, mem2_agu_res, mem2_ret_pc, mem2_csr_rdata} <= 
            {mem1_alu_res, mem1_agu_res, mem1_ret_pc, mem1_csr_rdata};
            mem2_rd <= mem1_rd; mem2_RegWen <= mem1_RegWen; 
            mem2_WbSel <= mem1_WbSel; mem2_funct3 <= mem1_funct3;
        end
    end
endmodule

// ==========================================
// 6. MEM2/WB Pipeline Register (极度精简)
// ==========================================
module MEM2_WB_Reg #(parameter DATAWIDTH = 32)(
    input  logic clk, rst, flush, stall,
    input  logic [DATAWIDTH-1:0] mem2_final_data, // 在 MEM2 阶段就全算好了
    input  logic [4:0]           mem2_rd,
    input  logic                 mem2_RegWen,

    output logic [DATAWIDTH-1:0] wb_data,
    output logic [4:0]           wb_rd,
    output logic                 wb_RegWen
);
    always_ff @(posedge clk) begin
        if (rst || flush) begin
            wb_data <= 0; wb_rd <= 0; wb_RegWen <= 0;
        end else if (!stall) begin
            wb_data <= mem2_final_data; wb_rd <= mem2_rd; wb_RegWen <= mem2_RegWen;
        end
    end
endmodule
