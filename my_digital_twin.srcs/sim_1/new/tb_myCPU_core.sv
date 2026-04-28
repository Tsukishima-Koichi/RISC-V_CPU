`timescale 1ns / 1ps


module tb_myCPU_core;
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

    // 2. 时钟生成 (外部晶振 200MHz -> 周期 5ns -> 半周�?? 2.5ns)
    initial begin
        clk = 0;
        forever #2.5 clk = ~clk;
    end

    // 3. 全新测试程序的死循环终点地址 (0xC8 = 200)
    localparam [31:0] HALT_PC = 32'h800000C8;
    
    integer drain_cnt = 0;
    integer timeout_cnt = 0;
    reg halt_detected = 0;

    // 4. 时钟块与结果校验
    always @(posedge uut.cpu_clk) begin
        
        // --- 机制 A：超时保护 ---
        timeout_cnt = timeout_cnt + 1;
        if (timeout_cnt > 15000 && !halt_detected) begin
            $display("========================================");
            $display("FAIL! Simulation Timeout.");
            $display("Current ID_PC: %h", uut.student_top_inst.Core_cpu.id_pc);
            $display("========================================");
            $finish;
        end

        // --- 机制 B：停机检测 (抓到一次就立 Flag) ---
        if (uut.student_top_inst.Core_cpu.id_inst == 32'h0000006f && 
            uut.student_top_inst.Core_cpu.id_pc == HALT_PC) begin
            halt_detected = 1; 
        end

        // --- 机制 C：排空流水线与结果校验 ---
        if (halt_detected) begin
            drain_cnt = drain_cnt + 1;
            
            // 等待 5 个周期，让之前的指令流完 WB 阶段
            if (drain_cnt >= 5) begin
                $display("========================================");
                $display("Simulation Halted Successfully at PC: %h", HALT_PC);
                
                // 校验包含冒险与前递逻辑的强相关寄存器
                if (uut.student_top_inst.Core_cpu.rf_inst.reg_bank[1]  == 32'h12345000 &&
                    uut.student_top_inst.Core_cpu.rf_inst.reg_bank[2]  == 32'h80000004 &&
                    uut.student_top_inst.Core_cpu.rf_inst.reg_bank[4]  == 32'd30 &&
                    uut.student_top_inst.Core_cpu.rf_inst.reg_bank[16] == 32'd120 &&
                    uut.student_top_inst.Core_cpu.rf_inst.reg_bank[21] == 32'd4 &&
                    uut.student_top_inst.Core_cpu.rf_inst.reg_bank[23] == 32'd15 &&
                    uut.student_top_inst.Core_cpu.rf_inst.reg_bank[24] == 32'h80000098 &&
                    uut.student_top_inst.Core_cpu.rf_inst.reg_bank[31] == 32'd15) begin
                    
                    $display(">>>> PASS! All 37 Instructions Verified! <<<<");
                    $display("Pipeline Hazards (Forwarding & Load-Use) Passed.");
                    $display("Branch Predictor (BHT/BTB Flush) Passed.");
                    
                end else begin
                    $display(">>>> FAIL! Pipeline or Hazard Bug Detected. <<<<");
                    $display("Expected vs Actual:");
                    $display("x1  (Exp: 12345000) : %h", uut.student_top_inst.Core_cpu.rf_inst.reg_bank[1]);
                    $display("x2  (Exp: 80000004) : %h", uut.student_top_inst.Core_cpu.rf_inst.reg_bank[2]);
                    $display("x4  (Exp: 30)       : %0d", uut.student_top_inst.Core_cpu.rf_inst.reg_bank[4]);
                    $display("x16 (Exp: 120)      : %0d", uut.student_top_inst.Core_cpu.rf_inst.reg_bank[16]);
                    $display("x21 (Exp: 4)        : %0d", uut.student_top_inst.Core_cpu.rf_inst.reg_bank[21]);
                    $display("x23 (Exp: 15)       : %0d", uut.student_top_inst.Core_cpu.rf_inst.reg_bank[23]);
                    $display("x24 (Exp: 80000098) : %h", uut.student_top_inst.Core_cpu.rf_inst.reg_bank[24]);
                    $display("x31 (Exp: 15)       : %0d", uut.student_top_inst.Core_cpu.rf_inst.reg_bank[31]);
                end
                
                $display("========================================");
                $finish;
            end
        end
    end

endmodule
