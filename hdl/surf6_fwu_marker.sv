`timescale 1ns / 1ps
// takes in a flag in sysclk from command decoder, outputs a gpo to PS,
// also takes in gpi from PS and uses it to clear the gpo and mark completed.
// also watches for a new write after the complete and kills the complete.
// lot of stuff going on here!
module surf6_fwu_marker(
        // sysclk clockdomain
        input sysclk_i,
        input fw_mark_i,
        input fw_wr_i,
        // WB clockdomain
        input wb_clk_i,
        output fw_pscomplete_o,
        // PS GP domain
        output ps_fwupdate_gpo_o,
        input ps_fwdone_gpi_i
    );
    
    wire clear_pscomplete_wbclk;
    flag_sync u_clear_pscomplete(.in_clkA(fw_wr_i), .out_clkB(clear_pscomplete_wbclk),
                                 .clkA(sysclk_i),.clkB(wb_clk_i));
    reg firmware_block_marked = 0;
    reg firmware_block_done = 0;

    reg [2:0] ps_fwdone_wbclk = {2{1'b0}};
    reg [2:0] ps_fwdone_sysclk = {2{1'b0}};

    always @(posedge sysclk_i) begin
        ps_fwdone_sysclk <= { ps_fwdone_sysclk[1:0], ps_fwdone_gpi_i };
        
        if (fw_mark_i) firmware_block_marked <= 1;
        else if (ps_fwdone_sysclk[2:1] == 2'b01) firmware_block_marked <= 0;        
    end
    
    always @(posedge wb_clk_i) begin
        ps_fwdone_wbclk <= { ps_fwdone_wbclk[1:0], ps_fwdone_gpi_i };
        if (ps_fwdone_wbclk[2:1] == 2'b01) firmware_block_done <= 1;
        else if (clear_pscomplete_wbclk) firmware_block_done <= 0;
    end
    
    assign fw_pscomplete_o = firmware_block_done;
    assign ps_fwupdate_gpo_o = firmware_block_marked;
        
endmodule
