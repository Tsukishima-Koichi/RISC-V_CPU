`timescale 1ns / 1ps

module BranchPredictor #(
    parameter PC_WIDTH = 32,
    parameter INDEX_BITS = 6 // 64个表项
)(
    input  logic                clk,
    input  logic                rst,
    
    // --- IF阶段查询端口 (Query) ---
    input  logic [PC_WIDTH-1:0] if_pc,
    output logic                pred_taken,
    output logic [PC_WIDTH-1:0] pred_target,
    
    // --- EX阶段更新端口 (Update) ---
    input  logic                ex_is_branch,     // 确认当前指令是分支/跳转指令
    input  logic [PC_WIDTH-1:0] ex_pc,            // EX阶段的PC
    input  logic                ex_actual_taken,  // 实际是否跳转
    input  logic [PC_WIDTH-1:0] ex_actual_target  // 实际跳转地址
);

    localparam TABLE_SIZE = 1 << INDEX_BITS;
    
    // 提取索引 (Index) 和 标签 (Tag)
    wire [INDEX_BITS-1:0]         if_idx = if_pc[INDEX_BITS+1 : 2]; // 忽略最低2位
    wire [PC_WIDTH-INDEX_BITS-3:0] if_tag = if_pc[PC_WIDTH-1 : INDEX_BITS+2];
    
    wire [INDEX_BITS-1:0]         ex_idx = ex_pc[INDEX_BITS+1 : 2];
    wire [PC_WIDTH-INDEX_BITS-3:0] ex_tag = ex_pc[PC_WIDTH-1 : INDEX_BITS+2];

    // BTB 表项结构
    logic [PC_WIDTH-INDEX_BITS-3:0] btb_tag    [TABLE_SIZE-1:0];
    logic [PC_WIDTH-1:0]            btb_target [TABLE_SIZE-1:0];
    logic                           btb_valid  [TABLE_SIZE-1:0];
    
    // BHT 表项结构 (2-bit饱和计数器)
    // 00: 强烈不跳, 01: 弱不跳, 10: 弱跳, 11: 强烈跳
    logic [1:0] bht_counter [TABLE_SIZE-1:0];

    // ----------------------------------------
    // 1. IF 阶段：预测逻辑 (纯组合逻辑)
    // ----------------------------------------
    wire tag_match = btb_valid[if_idx] && (btb_tag[if_idx] == if_tag);
    
    // 如果 Tag 命中，且 BHT 倾向于跳转 (最高位为1)
    assign pred_taken  = tag_match && bht_counter[if_idx][1];
    assign pred_target = btb_target[if_idx];

    // ----------------------------------------
    // 2. EX 阶段：更新逻辑 (时序逻辑)
    // ----------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < TABLE_SIZE; i++) begin
                btb_valid[i] <= 1'b0;
                bht_counter[i] <= 2'b01; // 默认弱不跳
            end
        end 
        else if (ex_is_branch) begin
            // 更新 BTB
            btb_valid[ex_idx]  <= 1'b1;
            btb_tag[ex_idx]    <= ex_tag;
            btb_target[ex_idx] <= ex_actual_target;
            
            // 更新 BHT (状态机)
            case (bht_counter[ex_idx])
                2'b00: bht_counter[ex_idx] <= ex_actual_taken ? 2'b01 : 2'b00;
                2'b01: bht_counter[ex_idx] <= ex_actual_taken ? 2'b10 : 2'b00;
                2'b10: bht_counter[ex_idx] <= ex_actual_taken ? 2'b11 : 2'b01;
                2'b11: bht_counter[ex_idx] <= ex_actual_taken ? 2'b11 : 2'b10;
            endcase
        end
    end
endmodule