`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/23/2025 03:50:55 PM
// Design Name: 
// Module Name: tb_myCPU
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module tb_myCPU;
    reg clk;

    top uut (
        .i_sys_clk_p(clk),
        .i_sys_clk_n(~clk),
        .i_uart_rx(1'b1),
        .o_uart_tx(),
        .virtual_led(),  
        .virtual_seg()
    );


    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    // test_src
    // 定义成功退出的 PC 地址 (RESET_VAL=0x8000_0000 + COE 偏移 0x10)
    localparam [31:0] HALT_PC = 32'h8000_0010; 

    always @(posedge clk) begin
        // 当执行到死循环指令时
        if (uut.student_top_inst.Core_cpu.inst == 32'h0000006f) begin
            $display("========================================");
            $display("Simulation Halted at PC: %h", uut.student_top_inst.Core_cpu.pc);
            
            // 判定逻辑：只有在指定的 PC 处停止，且 x10 为 0 才是真正通过
            if (uut.student_top_inst.Core_cpu.pc == HALT_PC && 
                uut.student_top_inst.Core_cpu.rf_inst.reg_bank[10] == 32'd0) begin
                $display("PASS! Test Suite Completed Successfully.");
            end else begin
                $display("FAIL! System Trapped or Error Occurred.");
                $display("Final x10 (Error Code): %0d", uut.student_top_inst.Core_cpu.rf_inst.reg_bank[10]);
                $display("Check PC and Instruction Trace for Debugging.");
            end
            
            $display("========================================");
            $finish;
        end
    end

    // test_core
    // always @(posedge clk) begin
    //     if (uut.student_top_inst.Core_cpu.inst == 32'h0000006f) begin
    //         $display("========================================");
            
    //         if (uut.student_top_inst.Core_cpu.rf_inst.reg_bank[10] == 32'd0) begin
    //             $display("PASS! (x10 = 0)");
    //         end else begin
    //             $display("FAIL! (x10 = %0d)", uut.student_top_inst.Core_cpu.rf_inst.reg_bank[10]);
    //         end
    //         $display("========================================");
            
    //         $finish;
    //     end
    // end
endmodule
