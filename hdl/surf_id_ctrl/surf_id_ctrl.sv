`timescale 1ns / 1ps
`include "interfaces.vh"
module surf_id_ctrl(
        input wb_clk_i,
        input wb_rst_i,
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 12, 32)
    );
endmodule
