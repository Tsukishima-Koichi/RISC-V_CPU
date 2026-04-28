`timescale 1ns / 1ps
`include "defines.sv"
`default_nettype none

module myCPU (
    input  wire          cpu_rst,
    input  wire          cpu_clk,

    output logic [31:0]  irom_addr,
    input  wire  [31:0]  irom_data,
    
    output logic [31:0]  perip_addr,
    output logic         perip_wen,
    output logic [ 3:0]  perip_mask,
    output logic [31:0]  perip_wdata,
    
    input  wire  [31:0]  perip_rdata
);
    parameter DATAWIDTH = 32;
    parameter RESET_VAL = 32'h8000_0000;

    // ==========================================
    // 全局信号提前声明
    // ==========================================
    // IF Stage
    logic [31:0] if_pc, next_pc, actual_next_pc;
    logic id_valid; 
    
    // --- 新增：IF阶段分支预测信号 ---
    logic pred_taken;
    logic [31:0] pred_target;
    logic [31:0] if_next_pc;

    // --- 新增：伴随 IF/ID 的预测流水线寄存器 ---
    logic id_pred_taken;
    logic [31:0] id_pred_target;
    
    // ID Stage
    logic [31:0] id_pc, id_inst;
    logic [31:0] id_branch_target; // 从 ID 阶段算好的分支目标地址
    logic [31:0] id_imm, id_rs1_data, id_rs2_data, id_ret_pc;
    logic id_IsBranch, id_RegWen, id_MemWen, id_AluSrcB;
    logic [1:0] id_JmpType, id_WbSel, id_AluSrcA;
    logic [3:0] id_alu_ctrl;
    logic id_CsrWen, id_CsrImmSel, id_IsEcall, id_IsEbreak, id_IsMret;
    logic [1:0] id_CsrOp;
    logic [31:0] id_forwarded_rs1, id_forwarded_rs2;
    logic [1:0] id_forward_A, id_forward_B;

    // --- 新增：伴随 ID/EX 的预测流水线寄存器 ---
    logic ex_pred_taken;
    logic [31:0] ex_pred_target;

    // EX Stage
    logic [31:0] ex_pc, ex_rs1_data, ex_rs2_data, ex_imm, ex_ret_pc;
    logic [31:0] ex_branch_target; // 从 ID 阶段流水传来的分支目标地址
    logic [4:0]  ex_rd, ex_rs1, ex_rs2;
    logic        ex_RegWen, ex_MemWen, ex_IsBranch, ex_AluSrcB;
    logic [1:0]  ex_JmpType, ex_WbSel, ex_AluSrcA;
    logic [3:0]  ex_alu_ctrl;
    logic [2:0]  ex_funct3;
    logic [11:0] ex_csr_idx;
    logic        ex_CsrWen, ex_CsrImmSel, ex_IsEcall, ex_IsEbreak, ex_IsMret;
    logic [1:0]  ex_CsrOp;
    logic [31:0] ex_csr_rdata;               
    logic [31:0] ex_csr_wdata;
    logic ex_actual_csr_wen;
    logic [31:0] ex_alu_op1, ex_alu_op2, ex_alu_res;
    logic        ex_take_trap;
    logic [31:0] trap_pc;
    logic [31:0] forwarded_rs1, forwarded_rs2; 
    logic [1:0] ex_forward_A, ex_forward_B; 
    logic [31:0] ex_agu_res;

    // --- 新增：EX阶段实际决断与预测验证信号 ---
    logic [31:0] ex_actual_target;
    logic [31:0] ex_pc_plus_4;
    logic        ex_actual_taken;
    logic        ex_mispredict;
    logic [31:0] recovery_pc;
    logic        ex_is_jump_or_branch;
    

    // MEM Stage
    logic [31:0] mem_alu_res, mem_rs2_data, mem_ret_pc;
    logic [4:0]  mem_rd;
    logic        mem_RegWen, mem_MemWen;
    logic [1:0]  mem_WbSel;
    logic [2:0]  mem_funct3;
    logic [31:0] mem_csr_rdata;
    logic [31:0] mem_fw_data; 
    logic [31:0] mem_agu_res;

    // WB Stage
    logic [31:0] wb_alu_res, wb_rdata_ext, wb_ret_pc;
    logic [4:0]  wb_rd;
    logic        wb_RegWen;
    logic [1:0]  wb_WbSel;
    logic [31:0] wb_csr_rdata;
    logic [31:0] wb_data;
    logic [31:0] wb_agu_res;
    logic [2:0]  wb_funct3;
    logic [31:0] wb_rdata_align;

    // ==========================================
    // 全局控制信号与冒险检测
    // ==========================================
    logic stall_IF, flush_IF_ID;
    logic stall_ID, flush_ID_EX;
    logic stall_EX, flush_EX_MEM;
    logic stall_MEM, flush_MEM_WB;
    
    assign stall_EX  = 1'b0;
    assign stall_MEM = 1'b0;
    assign flush_EX_MEM = 1'b0;
    assign flush_MEM_WB = 1'b0;

    logic hd_flush_ID_EX;
    HazardDetectionUnit hd_inst (
        .id_rs1      (id_inst[19:15]),
        .id_rs2      (id_inst[24:20]),
        .id_opcode   (id_inst[6:0]),
        .ex_RegWen   (ex_RegWen),
        .ex_WbSel    (ex_WbSel),
        .ex_rd       (ex_rd),
        .mem_WbSel   (mem_WbSel),
        .mem_rd      (mem_rd),
        .stall_IF    (stall_IF),
        .stall_ID    (stall_ID),
        .flush_ID_EX (hd_flush_ID_EX)
    );

    // 🌟 终极 PC 路由逻辑 (优先级: 异常 > 预测失败 > 分支预测)
    assign actual_next_pc = stall_IF       ? if_pc : 
                            ex_take_trap   ? trap_pc :
                            ex_mispredict  ? recovery_pc :
                                             if_next_pc;

    // 🌟 更新冲刷逻辑: 预测失败时必须冲刷 IF 和 ID 阶段拿错的指令
    assign flush_IF_ID = ex_mispredict | ex_take_trap; 
    assign flush_ID_EX = ex_mispredict | ex_take_trap | hd_flush_ID_EX;

    // ==========================================
    // Stage 1: IF (Instruction Fetch) & Prediction
    // ==========================================
    assign irom_addr = if_pc;

    PC #(DATAWIDTH, RESET_VAL) pc_inst (
        .clk(cpu_clk), .rst(cpu_rst),
        .npc(actual_next_pc), .pc_out(if_pc)
    );

    // 🌟 实例化动态分支预测器 (需要在工程中新建上文提到的 BranchPredictor.sv)
    BranchPredictor #(32, 6) bp_inst (
        .clk(cpu_clk), .rst(cpu_rst),
        
        .if_pc(if_pc),
        .pred_taken(pred_taken),
        .pred_target(pred_target),
        
        .ex_is_branch(ex_is_jump_or_branch),
        .ex_pc(ex_pc),
        .ex_actual_taken(ex_actual_taken),
        .ex_actual_target(ex_actual_target)
    );

    // 如果预测跳转则用预测目标，否则 PC+4
    assign if_next_pc = pred_taken ? pred_target : (if_pc + 4);

    IF_ID_Reg #(DATAWIDTH) if_id_reg (
        .clk(cpu_clk), .rst(cpu_rst), .flush(flush_IF_ID), .stall(stall_ID),
        .if_pc(if_pc),
        .id_pc(id_pc), .id_valid(id_valid) 
    );

    // 🌟 IF->ID 附加流水线：传递预测状态
    always_ff @(posedge cpu_clk) begin
        if (cpu_rst || flush_IF_ID) begin
            id_pred_taken  <= 1'b0;
            id_pred_target <= 32'b0;
        end else if (!stall_ID) begin
            id_pred_taken  <= pred_taken;
            id_pred_target <= pred_target;
        end
    end

    // ==========================================
    // Stage 2: ID (Instruction Decode)
    // ==========================================
    assign id_inst = id_valid ? irom_data : 32'h00000013; 

    assign id_ret_pc = id_pc + 4; 

    Control control_inst (
        .inst      (id_inst), 
        .IsBranch  (id_IsBranch), .JmpType (id_JmpType),
        .RegWen    (id_RegWen),   .MemWen  (id_MemWen),
        .WbSel     (id_WbSel),    .AluSrcA (id_AluSrcA), .AluSrcB (id_AluSrcB),
        .CsrWen(id_CsrWen), .CsrOp(id_CsrOp), .CsrImmSel(id_CsrImmSel), 
        .IsEcall(id_IsEcall), .IsEbreak(id_IsEbreak), .IsMret(id_IsMret)
    );

    IMMGEN #(DATAWIDTH) immgen_inst (.instr(id_inst), .imm(id_imm));

    ACTL actl_inst (
        .opcode   (id_inst[6:0]), .funct3 (id_inst[14:12]), .funct7 (id_inst[31:25]),
        .alu_ctrl (id_alu_ctrl)
    );

    RF #(5, DATAWIDTH) rf_inst (
        .clk(cpu_clk), .rst(cpu_rst), 
        .wen(wb_RegWen), .waddr(wb_rd), .wdata(wb_data),
        .rR1(id_inst[19:15]), .rR2(id_inst[24:20]), 
        .rR1_data(id_rs1_data), .rR2_data(id_rs2_data)
    );

    assign mem_fw_data = (mem_WbSel == 2'b01) ? mem_ret_pc : 
                         (mem_WbSel == 2'b11) ? mem_csr_rdata : mem_alu_res;

    ForwardingUnit fw_inst (
        .id_rs1(id_inst[19:15]), .id_rs2(id_inst[24:20]),
        .ex_RegWen(ex_RegWen),   .ex_rd(ex_rd),
        .mem_RegWen(mem_RegWen), .mem_rd(mem_rd),
        .id_forward_A(id_forward_A), .id_forward_B(id_forward_B)
    );

    // 在 ID 阶段独立且提前算好分支目标地址！
    assign id_branch_target = id_pc + id_imm;

    ID_EX_Reg #(DATAWIDTH) id_ex_reg (
        .clk(cpu_clk), .rst(cpu_rst), .flush(flush_ID_EX), .stall(stall_EX),
        .id_pc(id_pc), .id_rs1_data(id_rs1_data), .id_rs2_data(id_rs2_data), .id_imm(id_imm), .id_ret_pc(id_ret_pc),
        .id_rd(id_inst[11:7]), .id_rs1(id_inst[19:15]), .id_rs2(id_inst[24:20]),
        .id_RegWen(id_RegWen), .id_MemWen(id_MemWen), .id_IsBranch(id_IsBranch), .id_AluSrcB(id_AluSrcB),
        .id_JmpType(id_JmpType), .id_WbSel(id_WbSel), .id_AluSrcA(id_AluSrcA),
        .id_alu_ctrl(id_alu_ctrl), .id_funct3(id_inst[14:12]),
        .id_csr_idx(id_inst[31:20]), .id_CsrWen(id_CsrWen), .id_CsrImmSel(id_CsrImmSel), 
        .id_IsEcall(id_IsEcall), .id_IsEbreak(id_IsEbreak), .id_IsMret(id_IsMret), .id_CsrOp(id_CsrOp),
        .id_forward_A(id_forward_A), .id_forward_B(id_forward_B),
        .id_branch_target(id_branch_target),
        
        .ex_pc(ex_pc), .ex_rs1_data(ex_rs1_data), .ex_rs2_data(ex_rs2_data), .ex_imm(ex_imm), .ex_ret_pc(ex_ret_pc),
        .ex_rd(ex_rd), .ex_rs1(ex_rs1), .ex_rs2(ex_rs2),
        .ex_RegWen(ex_RegWen), .ex_MemWen(ex_MemWen), .ex_IsBranch(ex_IsBranch), .ex_AluSrcB(ex_AluSrcB),
        .ex_JmpType(ex_JmpType), .ex_WbSel(ex_WbSel), .ex_AluSrcA(ex_AluSrcA),
        .ex_alu_ctrl(ex_alu_ctrl), .ex_funct3(ex_funct3),
        .ex_csr_idx(ex_csr_idx), .ex_CsrWen(ex_CsrWen), .ex_CsrImmSel(ex_CsrImmSel),
        .ex_IsEcall(ex_IsEcall), .ex_IsEbreak(ex_IsEbreak), .ex_IsMret(ex_IsMret), .ex_CsrOp(ex_CsrOp),
        .ex_forward_A(ex_forward_A), .ex_forward_B(ex_forward_B),
        .ex_branch_target(ex_branch_target)
    );

    // 🌟 ID->EX 附加流水线：传递预测状态到决断阶段
    always_ff @(posedge cpu_clk) begin
        if (cpu_rst || flush_ID_EX) begin
            ex_pred_taken  <= 1'b0;
            ex_pred_target <= 32'b0;
        end else if (!stall_EX) begin
            ex_pred_taken  <= id_pred_taken;
            ex_pred_target <= id_pred_target;
        end
    end

    // ==========================================
    // Stage 3: EX (Execute) & Branch Resolution
    // ==========================================
    always_comb begin
        case (ex_forward_A) 
            2'b10:   forwarded_rs1 = mem_fw_data;
            2'b01:   forwarded_rs1 = wb_data;
            default: forwarded_rs1 = ex_rs1_data;
        endcase
    end

    always_comb begin
        case (ex_forward_B) 
            2'b10:   forwarded_rs2 = mem_fw_data;
            2'b01:   forwarded_rs2 = wb_data;
            default: forwarded_rs2 = ex_rs2_data;
        endcase
    end

    // ----------------------------------------
    // 核心：在此决断分支/跳转是否正确
    // ----------------------------------------
    assign ex_is_jump_or_branch = ex_IsBranch || (ex_JmpType != 2'b00);

    BranchUnit #(DATAWIDTH) bu_inst (
        .imm(ex_imm), // 注意去掉了 pc 端口
        .rs1_data(forwarded_rs1), .rs2_data(forwarded_rs2),
        
        // 传入提前算好的两个地址
        .precalc_branch_target(ex_branch_target), 
        .precalc_pc_plus_4(ex_ret_pc), // 直接使用流水线传下来的返回地址
        
        .trap_pc(32'b0), 
        .Branch(ex_IsBranch), .Jump(ex_JmpType), .funct3(ex_funct3),
        .next_pc(ex_actual_target), .pc_plus_4(ex_pc_plus_4) 
    );

    assign ex_actual_taken = (ex_actual_target != ex_pc_plus_4);

    // 检测预测失误 (Mispredict Logic)
    wire mispredict_taken     = ex_actual_taken && (!ex_pred_taken || (ex_pred_target != ex_actual_target));
    wire mispredict_not_taken = !ex_actual_taken && ex_pred_taken;
    
    // 如果预测器胡乱预测跳转 (非跳转指令被误判)，也触发纠正
    assign ex_mispredict = (ex_is_jump_or_branch && (mispredict_taken | mispredict_not_taken)) || 
                           (!ex_is_jump_or_branch && ex_pred_taken);

    // 算出该恢复到哪里：真该跳就跳目标，否则回退到 PC+4
    assign recovery_pc = ex_actual_taken ? ex_actual_target : ex_pc_plus_4;

    // ----------------------------------------
    // 常规运算单元
    // ----------------------------------------
    assign ex_alu_op1 = (ex_AluSrcA == 2'b10) ? 32'b0 :
                        (ex_AluSrcA == 2'b01) ? ex_pc : forwarded_rs1;
    assign ex_alu_op2 =  ex_AluSrcB           ? ex_imm : forwarded_rs2;

    ALU #(DATAWIDTH) alu_inst (
        .A(ex_alu_op1), .B(ex_alu_op2), .ALUControl(ex_alu_ctrl), .Result(ex_alu_res)
    );

    AGU #(DATAWIDTH) agu_inst (
        .base   (forwarded_rs1), 
        .offset (ex_imm),
        .addr   (ex_agu_res)
    );

    assign ex_csr_wdata = ex_CsrImmSel ? {27'b0, ex_rs1} : forwarded_rs1;
    assign ex_actual_csr_wen = ex_CsrWen && !((ex_CsrOp == 2'b10 || ex_CsrOp == 2'b11) && (ex_rs1 == 5'b0));

    CSR #(DATAWIDTH) csr_inst (
        .clk(cpu_clk), .rst(cpu_rst), .pc(ex_pc),
        .csr_idx(ex_csr_idx), .wdata(ex_csr_wdata), .csr_op(ex_CsrOp), .csr_wen(ex_actual_csr_wen),
        .ecall(ex_IsEcall), .ebreak(ex_IsEbreak), .mret(ex_IsMret),
        .rdata(ex_csr_rdata), .trap_pc(trap_pc)
    );
    assign ex_take_trap = ex_IsEcall | ex_IsEbreak | ex_IsMret;

    EX_MEM_Reg #(DATAWIDTH) ex_mem_reg (
        .clk(cpu_clk), .rst(cpu_rst), .flush(flush_EX_MEM), .stall(stall_MEM),
        .ex_alu_res(ex_alu_res), .ex_agu_res(ex_agu_res),      
        .ex_rs2_data(forwarded_rs2), .ex_ret_pc(ex_ret_pc),
        .ex_rd(ex_rd), .ex_RegWen(ex_RegWen), .ex_MemWen(ex_MemWen), .ex_WbSel(ex_WbSel), .ex_funct3(ex_funct3),
        .ex_csr_rdata(ex_csr_rdata),
        
        .mem_alu_res(mem_alu_res), .mem_agu_res(mem_agu_res),    
        .mem_rs2_data(mem_rs2_data), .mem_ret_pc(mem_ret_pc),
        .mem_rd(mem_rd), .mem_RegWen(mem_RegWen), .mem_MemWen(mem_MemWen), 
        .mem_WbSel(mem_WbSel), .mem_funct3(mem_funct3), .mem_csr_rdata(mem_csr_rdata)
    );

    // ==========================================
    // Stage 4: MEM (Memory Access)
    // ==========================================
    assign perip_addr = mem_agu_res;
    assign perip_wen  = mem_MemWen;

    StoreAlign #(DATAWIDTH) store_align_inst (
        .addr_offset (mem_agu_res[1:0]), 
        .wdata_in    (mem_rs2_data),
        .size_mask   (mem_funct3[1:0]), 
        .MemWrite    (mem_MemWen),
        .wmask_out   (perip_mask),   
        .wdata_out   (perip_wdata)   
    );

    MEM_WB_Reg #(DATAWIDTH) mem_wb_reg (
        .clk(cpu_clk), .rst(cpu_rst), .flush(flush_MEM_WB), .stall(1'b0),
        .mem_alu_res(mem_alu_res), .mem_ret_pc(mem_ret_pc),
        .mem_agu_res(mem_agu_res), .mem_funct3(mem_funct3), 
        .mem_rd(mem_rd), .mem_RegWen(mem_RegWen), .mem_WbSel(mem_WbSel),
        .mem_csr_rdata(mem_csr_rdata),

        .wb_alu_res(wb_alu_res), .wb_ret_pc(wb_ret_pc),
        .wb_agu_res(wb_agu_res), .wb_funct3(wb_funct3),     
        .wb_rd(wb_rd), .wb_RegWen(wb_RegWen), .wb_WbSel(wb_WbSel), .wb_csr_rdata(wb_csr_rdata)
    );

    // ==========================================
    // Stage 5: WB (Write Back)
    // ==========================================
    always_comb begin
        case (wb_funct3) 
            3'b000, 3'b100: wb_rdata_align = perip_rdata >> (8 * wb_agu_res[1:0]);
            3'b001, 3'b101: wb_rdata_align = perip_rdata >> (16 * wb_agu_res[1]);  
            default:        wb_rdata_align = perip_rdata;
        endcase
    end

    Mask #(DATAWIDTH) mask_inst (
        .mask(wb_funct3), .dout(wb_rdata_align), .mdata(wb_rdata_ext)
    );

    always_comb begin
        case (wb_WbSel) 
            2'b01:   wb_data = wb_ret_pc;
            2'b10:   wb_data = wb_rdata_ext;
            2'b11:   wb_data = wb_csr_rdata;
            default: wb_data = wb_alu_res;
        endcase
    end

endmodule