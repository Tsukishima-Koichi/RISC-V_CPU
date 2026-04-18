`timescale 1ns / 1ps
`include "defines.sv"

module myCPU (
    input  logic         cpu_rst,
    input  logic         cpu_clk,

    output logic [31:0]  irom_addr,
    input  logic [31:0]  irom_data,
    
    output logic [31:0]  perip_addr,
    output logic         perip_wen,
    output logic [ 3:0]  perip_mask,
    output logic [31:0]  perip_wdata,
    
    input  logic [31:0]  perip_rdata
);
    parameter DATAWIDTH = 32;
    parameter RESET_VAL = 32'h8000_0000;

    // ==========================================
    // 全局信号提前声明 (防止未声明先使用)
    // ==========================================
    // IF Stage
    logic [31:0] if_pc, next_pc, actual_next_pc;
    logic id_valid; // 新增;
    
    // ID Stage
    logic [31:0] id_pc, id_inst;
    logic [31:0] id_imm, id_rs1_data, id_rs2_data, id_ret_pc;
    logic id_IsBranch, id_RegWen, id_MemWen, id_AluSrcB;
    logic [1:0] id_JmpType, id_WbSel, id_AluSrcA;
    logic [3:0] id_alu_ctrl;
    logic id_CsrWen, id_CsrImmSel, id_IsEcall, id_IsEbreak, id_IsMret;
    logic [1:0] id_CsrOp;
    logic id_take_branch;
    logic [31:0] jump_branch_pc; 
    logic [31:0] id_forwarded_rs1, id_forwarded_rs2;
    logic [1:0] id_forward_A, id_forward_B; // 预计算的前递信号

    // EX Stage
    logic [31:0] ex_pc, ex_rs1_data, ex_rs2_data, ex_imm, ex_ret_pc;
    logic [4:0]  ex_rd, ex_rs1, ex_rs2;
    logic        ex_RegWen, ex_MemWen, ex_IsBranch, ex_AluSrcB;
    logic [1:0]  ex_JmpType, ex_WbSel, ex_AluSrcA;
    logic [3:0]  ex_alu_ctrl;
    logic [2:0]  ex_funct3;
    logic [11:0] ex_csr_idx;
    logic        ex_CsrWen, ex_CsrImmSel, ex_IsEcall, ex_IsEbreak, ex_IsMret;
    logic [1:0]  ex_CsrOp;
    logic [31:0] ex_alu_op1, ex_alu_op2, ex_alu_res;
    logic        ex_take_trap;
    logic [31:0] trap_pc;
    logic [31:0] forwarded_rs1, forwarded_rs2; // 旁路前递后的源操作数
    logic [31:0] ex_csr_rdata;                 // CSR 读出的数据
    logic ex_actual_csr_wen;
    logic [1:0] ex_forward_A, ex_forward_B; // EX阶段直接使用的前递信号
    logic [31:0] ex_agu_res;

    // MEM Stage
    logic [31:0] mem_alu_res, mem_rs2_data, mem_ret_pc;
    logic [4:0]  mem_rd;
    logic        mem_RegWen, mem_MemWen;
    logic [1:0]  mem_WbSel;
    logic [2:0]  mem_funct3;
    logic [31:0] mem_csr_rdata;
    logic [31:0] mem_fw_data; // 动态选择的真实旁路数据
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

    // 终极 PC 路由逻辑
    assign next_pc = ex_take_trap   ? trap_pc :
                     id_take_branch ? jump_branch_pc : 
                     if_pc + 4;

    assign flush_IF_ID = id_take_branch | ex_take_trap; 
    assign flush_ID_EX = ex_take_trap | hd_flush_ID_EX;

    // ==========================================
    // Stage 1: IF (Instruction Fetch)
    // ==========================================
    assign irom_addr = if_pc;

    assign actual_next_pc = stall_IF ? if_pc : next_pc;

    PC #(DATAWIDTH, RESET_VAL) pc_inst (
        .clk(cpu_clk), .rst(cpu_rst),
        .npc(actual_next_pc), .pc_out(if_pc)
    );

    IF_ID_Reg #(DATAWIDTH) if_id_reg (
        .clk(cpu_clk), .rst(cpu_rst), .flush(flush_IF_ID), .stall(stall_ID),
        .if_pc(if_pc),
        .id_pc(id_pc), .id_valid(id_valid) // 🌟 接收 valid 信号
    );

    // ==========================================
    // Stage 2: ID (Instruction Decode)
    // ==========================================
    // 核心同步逻辑：如果有效，直接使用 BRAM 刚吐出的 irom_data；如果被冲刷，塞入 NOP
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

    // 🌟 修复 Bug 核心：动态选择 MEM 阶段的真实写回数据
    assign mem_fw_data = (mem_WbSel == 2'b01) ? mem_ret_pc : 
                         (mem_WbSel == 2'b11) ? mem_csr_rdata : mem_alu_res;

    // ID 阶段微型前递
    always_comb begin
        if (mem_RegWen && (mem_rd != 0) && (mem_rd == id_inst[19:15]) && (mem_WbSel != 2'b10)) 
            id_forwarded_rs1 = mem_fw_data; // 不再硬编码 alu_res，安全了！
        else if (wb_RegWen && (wb_rd != 0) && (wb_rd == id_inst[19:15])) 
            id_forwarded_rs1 = wb_data;
        else 
            id_forwarded_rs1 = id_rs1_data;
    end

    always_comb begin
        if (mem_RegWen && (mem_rd != 0) && (mem_rd == id_inst[24:20]) && (mem_WbSel != 2'b10)) 
            id_forwarded_rs2 = mem_fw_data;
        else if (wb_RegWen && (wb_rd != 0) && (wb_rd == id_inst[24:20])) 
            id_forwarded_rs2 = wb_data;
        else 
            id_forwarded_rs2 = id_rs2_data;
    end

    // 将前递判定逻辑前移到 ID 阶段
    ForwardingUnit fw_inst (
        .id_rs1(id_inst[19:15]), .id_rs2(id_inst[24:20]),
        .ex_RegWen(ex_RegWen),   .ex_rd(ex_rd),
        .mem_RegWen(mem_RegWen), .mem_rd(mem_rd),
        .id_forward_A(id_forward_A), .id_forward_B(id_forward_B)
    );

    BranchUnit #(DATAWIDTH) bu_inst (
        .pc(id_pc), .imm(id_imm),
        .rs1_data(id_forwarded_rs1), .rs2_data(id_forwarded_rs2),
        .trap_pc(32'b0), 
        .Branch(id_IsBranch), .Jump(id_JmpType), .funct3(id_inst[14:12]),
        .next_pc(jump_branch_pc), .pc_plus_4() 
    );

    assign id_take_branch = (jump_branch_pc != id_ret_pc);

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
        
        .ex_pc(ex_pc), .ex_rs1_data(ex_rs1_data), .ex_rs2_data(ex_rs2_data), .ex_imm(ex_imm), .ex_ret_pc(ex_ret_pc),
        .ex_rd(ex_rd), .ex_rs1(ex_rs1), .ex_rs2(ex_rs2),
        .ex_RegWen(ex_RegWen), .ex_MemWen(ex_MemWen), .ex_IsBranch(ex_IsBranch), .ex_AluSrcB(ex_AluSrcB),
        .ex_JmpType(ex_JmpType), .ex_WbSel(ex_WbSel), .ex_AluSrcA(ex_AluSrcA),
        .ex_alu_ctrl(ex_alu_ctrl), .ex_funct3(ex_funct3),
        .ex_csr_idx(ex_csr_idx), .ex_CsrWen(ex_CsrWen), .ex_CsrImmSel(ex_CsrImmSel),
        .ex_IsEcall(ex_IsEcall), .ex_IsEbreak(ex_IsEbreak), .ex_IsMret(ex_IsMret), .ex_CsrOp(ex_CsrOp),
        .ex_forward_A(ex_forward_A), .ex_forward_B(ex_forward_B)
    );

    // ==========================================
    // Stage 3: EX (Execute)
    // ==========================================
    always_comb begin
        case (ex_forward_A) // <--- 改用流水线传过来的 ex_forward_A
            2'b10:   forwarded_rs1 = mem_fw_data; 
            2'b01:   forwarded_rs1 = wb_data;
            default: forwarded_rs1 = ex_rs1_data;
        endcase
    end

    always_comb begin
        case (ex_forward_B) // <--- 改用流水线传过来的 ex_forward_B
            2'b10:   forwarded_rs2 = mem_fw_data;
            2'b01:   forwarded_rs2 = wb_data;
            default: forwarded_rs2 = ex_rs2_data; 
        endcase
    end

    assign ex_alu_op1 = (ex_AluSrcA == 2'b10) ? 32'b0 :
                        (ex_AluSrcA == 2'b01) ? ex_pc : forwarded_rs1;
    assign ex_alu_op2 =  ex_AluSrcB           ? ex_imm : forwarded_rs2;

    // 原有的 ALU 例化
    ALU #(DATAWIDTH) alu_inst (
        .A(ex_alu_op1), .B(ex_alu_op2), .ALUControl(ex_alu_ctrl), .Result(ex_alu_res)
    );

    // 专属访存地址生成单元 (AGU)
    // 强制使用 rs1 和 imm 计算，不受 AluSrc 控制信号的多路选择器延迟影响！
    AGU #(DATAWIDTH) agu_inst (
        .base   (forwarded_rs1), 
        .offset (ex_imm),
        .addr   (ex_agu_res)
    );

    // CSR 与 异常处理

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
        .ex_alu_res(ex_alu_res), .ex_agu_res(ex_agu_res),      // <--- 接入 AGU 结果
        .ex_rs2_data(forwarded_rs2), .ex_ret_pc(ex_ret_pc),
        .ex_rd(ex_rd), .ex_RegWen(ex_RegWen), .ex_MemWen(ex_MemWen), .ex_WbSel(ex_WbSel), .ex_funct3(ex_funct3),
        .ex_csr_rdata(ex_csr_rdata),
        
        .mem_alu_res(mem_alu_res), .mem_agu_res(mem_agu_res),    // <--- 接出 AGU 结果
        .mem_rs2_data(mem_rs2_data), .mem_ret_pc(mem_ret_pc),
        .mem_rd(mem_rd), .mem_RegWen(mem_RegWen), .mem_MemWen(mem_MemWen), 
        .mem_WbSel(mem_WbSel), .mem_funct3(mem_funct3), .mem_csr_rdata(mem_csr_rdata)
    );

    // ==========================================
    // Stage 4: MEM (Memory Access)
    // ==========================================
    assign perip_addr = mem_agu_res; // 送往外设和内存的地址改用 AGU 结果
    assign perip_wen  = mem_MemWen;    

    StoreAlign #(DATAWIDTH) store_align_inst (
        .addr_offset (mem_agu_res[1:0]), // 修改为 AGU
        .wdata_in    (mem_rs2_data),
        .size_mask   (mem_funct3[1:0]), 
        .MemWrite    (mem_MemWen),
        .wmask_out   (perip_mask),   
        .wdata_out   (perip_wdata)   
    );

    MEM_WB_Reg #(DATAWIDTH) mem_wb_reg (
     .clk(cpu_clk), .rst(cpu_rst), .flush(flush_MEM_WB), .stall(1'b0),
     .mem_alu_res(mem_alu_res), .mem_ret_pc(mem_ret_pc),
     .mem_agu_res(mem_agu_res), .mem_funct3(mem_funct3), // 🌟 传入
     .mem_rd(mem_rd), .mem_RegWen(mem_RegWen), .mem_WbSel(mem_WbSel),
     .mem_csr_rdata(mem_csr_rdata),

     .wb_alu_res(wb_alu_res), .wb_ret_pc(wb_ret_pc),
     .wb_agu_res(wb_agu_res), .wb_funct3(wb_funct3),     // 🌟 传出
     .wb_rd(wb_rd), .wb_RegWen(wb_RegWen), .wb_WbSel(wb_WbSel), .wb_csr_rdata(wb_csr_rdata)
 );

    // ==========================================
    // Stage 5: WB (Write Back)
    // ==========================================
    // 将 Mask 模块放置在这里，直接处理刚收到的 perip_rdata
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