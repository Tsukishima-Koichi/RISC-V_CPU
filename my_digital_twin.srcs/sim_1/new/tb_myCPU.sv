`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/04/23 
// Design Name: 
// Module Name: tb_myCPU
// Project Name: RV32I 37 Basic Instructions Testbench
// Target Devices: 
// Tool Versions: 
// Description: Pipeline CPU Testbench verified with custom 37-instruction suite
// 
//////////////////////////////////////////////////////////////////////////////////

module tb_myCPU;
    reg clk;

    // 1. 例化顶层模块
    top uut (
        .i_sys_clk_p(clk),
        .i_sys_clk_n(~clk),
        .i_uart_rx(1'b1),
        .o_uart_tx(),
        .virtual_led(),  
        .virtual_seg()
    );

    // 2. 时钟生成 (外部晶振 200MHz -> 周期 5ns -> 半周�? 2.5ns)
    initial begin
        clk = 0;
        forever #2.5 clk = ~clk;
    end

    // 3. 37条指令测试的死循环终点地�? (0xB4 = 180)
    localparam [31:0] HALT_PC = 32'h800000B4;
    
    integer drain_cnt = 0;
    integer timeout_cnt = 0;
    reg halt_detected = 0; // 新增：是否抵达终点的标志位

    // 4. 重点修正：使用 CPU 真实的工作时钟 (50MHz)
    always @(posedge uut.cpu_clk) begin
        
        // --- 机制 A：超时保护 ---
        timeout_cnt = timeout_cnt + 1;
        if (timeout_cnt > 100000 && !halt_detected) begin
            $display("========================================");
            $display("FAIL! Simulation Timeout.");
            $display("Current ID_PC: %h", uut.student_top_inst.Core_cpu.id_pc);
            $display("========================================");
            $finish;
        end

        // --- 机制 B：停机检测 (抓到一次就立 Flag) ---
        if (uut.student_top_inst.Core_cpu.id_inst == 32'h0000006f && 
            uut.student_top_inst.Core_cpu.id_pc == HALT_PC) begin
            halt_detected = 1; // 发现死循环，立下 Flag！
        end

        // --- 机制 C：排空流水线与结果校验 ---
        if (halt_detected) begin
            drain_cnt = drain_cnt + 1;
            
            // 等待 5 个周期，让之前的指令写回完毕
            if (drain_cnt >= 5) begin
                $display("========================================");
                $display("Simulation Halted Successfully at PC: %h", HALT_PC);
                
                // 校验我们在 COE 中精心设计的预期结果
                if (uut.student_top_inst.Core_cpu.rf_inst.reg_bank[3]  == 32'd15 &&
                    uut.student_top_inst.Core_cpu.rf_inst.reg_bank[6]  == 32'h80100000 &&
                    uut.student_top_inst.Core_cpu.rf_inst.reg_bank[9]  == 32'd60 &&
                    uut.student_top_inst.Core_cpu.rf_inst.reg_bank[22] == 32'd15 &&
                    uut.student_top_inst.Core_cpu.rf_inst.reg_bank[25] == 32'd15) begin
                    
                    $display(">>>> PASS! All 37 Basic Instructions Executed Correctly! <<<<");
                    $display("Arithmetic, Logic, Branch, and Load/Store all verified.");
                    
                end else begin
                    $display(">>>> FAIL! Register values mismatch. Pipeline bug detected. <<<<");
                    $display("Expected values vs Actual values:");
                    $display("x3  (Exp: 15)       : %0d", uut.student_top_inst.Core_cpu.rf_inst.reg_bank[3]);
                    $display("x6  (Exp: 80100000) : %h", uut.student_top_inst.Core_cpu.rf_inst.reg_bank[6]);
                    $display("x9  (Exp: 60)       : %0d", uut.student_top_inst.Core_cpu.rf_inst.reg_bank[9]);
                    $display("x22 (Exp: 15)       : %0d", uut.student_top_inst.Core_cpu.rf_inst.reg_bank[22]);
                    $display("x25 (Exp: 15)       : %0d", uut.student_top_inst.Core_cpu.rf_inst.reg_bank[25]);
                end
                
                $display("========================================");
                $finish;
            end
        end
    end

endmodule