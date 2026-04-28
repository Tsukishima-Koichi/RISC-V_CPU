`timescale 1ns / 1ps
`include "defines.sv"

module myCPU (
    input  logic         cpu_rst,
    input  logic         cpu_clk,

    // Instruction Memory Interface (指令内存接口)
    output logic [31:0]  irom_addr,
    input  logic [31:0]  irom_data,
    
    // Data Memory / Peripheral Interface (数据内存/外设接口)
    output logic [31:0]  perip_addr,
    output logic         perip_wen,
    output logic [ 3:0]  perip_mask,
    output logic [31:0]  perip_wdata,
    input  logic [31:0]  perip_rdata
);
    parameter DATAWIDTH = 32;
    parameter RESET_VAL = 32'h8000_0000;
    
    // ==========================================
    // 内部规范化线缆声明 (Internal Wires)
    // ==========================================
    // 1. 指令获取与程序计数 (IF Stage)
    logic [31:0] next_pc, pc, inst, imm;
    logic [31:0] ret_pc;       // 规范：pc_plus_4 -> ret_pc (返回地址)
    
    // 2. 寄存器堆数据 (RF Data)
    logic [31:0] rs1_data, rs2_data, wb_data; // wb_data = Write-Back Data
    
    // 3. ALU 操作数与结果 (ALU Data)
    logic [31:0] alu_op1, alu_op2, alu_res;   // 规范：alu_a/b -> op1/op2
    logic [ 3:0] alu_ctrl;
    
    // 4. 控制信号 (Control Signals)
    logic        IsBranch, RegWen, MemWen;  
    logic [ 1:0] JmpType, WbSel, AluSrcA;
    logic        AluSrcB;

    // 5. CSR 与 特权状态 (CSR Data)
    logic        CsrWen, CsrImmSel, IsEcall, IsEbreak, IsMret;
    logic [ 1:0] CsrOp;
    logic [31:0] csr_wdata, csr_rdata, trap_pc;

    // ==========================================
    // 逻辑实例连接 (Instances)
    // ==========================================
    assign irom_addr = pc;
    assign inst      = irom_data;

    PC #(DATAWIDTH, RESET_VAL) pc_inst (
        .clk(cpu_clk), .rst(cpu_rst),
        .npc(next_pc), .pc_out(pc)
    );

    Control control_inst (
        .inst      (inst)      , 
        .IsBranch  (IsBranch)  ,
        .JmpType   (JmpType)   ,
        .RegWen    (RegWen)    ,
        .MemWen    (MemWen)    ,
        .WbSel     (WbSel)     ,
        .AluSrcA   (AluSrcA)   ,
        .AluSrcB   (AluSrcB)   ,
        .CsrWen    (CsrWen)    ,
        .CsrOp     (CsrOp)     ,
        .CsrImmSel (CsrImmSel) ,
        .IsEcall   (IsEcall)   ,
        .IsEbreak  (IsEbreak)  ,
        .IsMret    (IsMret)
    );

    IMMGEN #(DATAWIDTH) immgen_inst (.instr(inst), .imm(imm)); // 映射到旧接口 instr

    RF #(5, DATAWIDTH) rf_inst (
        .clk(cpu_clk), .rst(cpu_rst), 
        .wen(RegWen),                 // 连接规范化的 RegWen
        .waddr(inst[11:7]), .wdata(wb_data), 
        .rR1(inst[19:15]),  .rR2(inst[24:20]), 
        .rR1_data(rs1_data),.rR2_data(rs2_data)
    );

    BranchUnit #(DATAWIDTH) bu_inst (
        .pc(pc), .imm(imm),
        .rs1_data(rs1_data), .rs2_data(rs2_data), 
        .trap_pc(trap_pc),
        .Branch(IsBranch), .Jump(JmpType), .funct3(inst[14:12]), // 映射控制信号
        .next_pc(next_pc), .pc_plus_4(ret_pc)
    );

    ACTL actl_inst (
        .opcode       (inst[6:0]),
        .funct3       (inst[14:12]),
        .funct7       (inst[31:25]),
        .alu_ctrl     (alu_ctrl)
    );

    // ALU 数据源多路选择器
    assign alu_op1 = (AluSrcA == 2'b10) ? 32'b0 :
                     (AluSrcA == 2'b01) ? pc    : rs1_data;
    assign alu_op2 =  AluSrcB           ? imm   : rs2_data;

    ALU #(DATAWIDTH) alu_inst (
        .A(alu_op1), .B(alu_op2), .ALUControl(alu_ctrl), .Result(alu_res)
    );

    // ==========================================
    // CSR 与 异常处理
    // ==========================================
    logic actual_csr_wen;
    assign actual_csr_wen = CsrWen && !((CsrOp == 2'b10 || CsrOp == 2'b11) && (inst[19:15] == 5'b0));
    assign csr_wdata = CsrImmSel ? {27'b0, inst[19:15]} : rs1_data;

    CSR #(DATAWIDTH) csr_inst (
        .clk        (cpu_clk),
        .rst        (cpu_rst),
        .pc         (pc),
        .csr_idx    (inst[31:20]),
        .wdata      (csr_wdata),
        .csr_op     (CsrOp),
        .csr_wen    (actual_csr_wen),
        .ecall      (IsEcall),
        .ebreak     (IsEbreak),
        .mret       (IsMret),
        .rdata      (csr_rdata),
        .trap_pc    (trap_pc)
    );

    // ==========================================
    // 访存逻辑 (Data Memory Interface)
    // ==========================================
    assign perip_addr = alu_res;
    assign perip_wen  = MemWen;    
    
    StoreAlign #(DATAWIDTH) store_align_inst (
        .addr_offset (alu_res[1:0]),
        .wdata_in    (rs2_data),
        .size_mask   (inst[13:12]), 
        .MemWrite    (MemWen),
        .wmask_out   (perip_mask),   
        .wdata_out   (perip_wdata)   
    );
    
    logic [31:0] mem_rdata_align; // 规范：aligned_rdata -> mem_rdata_align
    always_comb begin
        case (inst[14:12]) 
            3'b000, 3'b100: mem_rdata_align = perip_rdata >> (8 * alu_res[1:0]); 
            3'b001, 3'b101: mem_rdata_align = perip_rdata >> (16 * alu_res[1]);  
            default:        mem_rdata_align = perip_rdata;                          
        endcase
    end
    
    logic [31:0] mem_rdata_ext; // 规范：loaded_data -> mem_rdata_ext (扩展后数据)
    Mask #(DATAWIDTH) mask_inst (
        .mask   (inst[14:12]), 
        .dout   (mem_rdata_align), 
        .mdata  (mem_rdata_ext)
    );

    // ==========================================
    // 写回多路选择器 (Write-Back Mux)
    // ==========================================
    always_comb begin
        case (WbSel) // 规范：根据 WbSel 选择写回数据
            2'b01:   wb_data = ret_pc;          // JAL/JALR
            2'b10:   wb_data = mem_rdata_ext;   // 内存读出
            2'b11:   wb_data = csr_rdata;       // CSR 读出
            default: wb_data = alu_res;         // ALU 运算结果
        endcase
    end

endmodule