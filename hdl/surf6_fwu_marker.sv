`timescale 1ns / 1ps
// takes in a flag in sysclk from command decoder, outputs a gpo to PS,
// also takes in gpi from PS and uses it to clear the gpo and mark completed.
// also watches for a new write after the complete and kills the complete.
// lot of stuff going on here!
//
// YET MORE updating!
// The way this works NOW is to resolve a final race between the SURF
// being put in eDownloadMode and pyfwupd starting up. So we plumb in
// the download mode indicator (bit[7] from the ctrlstat reg): IF download
// mode is NOT set, we CLEAR both pscompletes. ONCE download mode IS
// set, pyfwupd starts up and AFTER IT OPENS THE INPUT FILE (so it won't
// miss anything!) it toggles BOTH the fwdones high then low, which
// sets the pscompletes. The pscompletes now look like "this bank is ready".
module surf6_fwu_marker(
        // sysclk clockdomain
        input sysclk_i,
        input ifclk_i,
        input [1:0] fw_mark_i,
        input [1:0] fw_wr_i,
        // WB clockdomain
        input wb_clk_i,
        input fw_downloadmode_i,
        output [1:0] fw_pscomplete_o,
        // PS GP domain
        output [1:0] ps_fwupdate_gpo_o,
        input [1:0] ps_fwdone_gpi_i
    );
    // this is cleaned up a bit:
    // we now have two half-buffers, A and B
    
    // software side:
    // 0. start up and check if both pscomplete[1:0] are set (pyfwupd is running)
    // 1. write to A, and mark A
    // 2. write to B, and mark B
    // 3. check pscomplete[0], and if pscomplete[0], write A, and mark A
    // 4. check pscomplete[1], and if pscomplete[1], write B, and mark B
    // 5. go to step 3
    // PS side:
    // 0. start up and set fwdone[1:0] and clear both
    // 1. wait for ps_fwupdate_gpo[0]
    // 2. readout A, set/clear fwdone[0]
    // 3. wait for ps_fwupdate_gpo[1]
    // 4. readout B, set/clear fwdone[1]
    // 5. go to step 1
    // firmware side:
    // 0. !download_i clears pscomplete[1:0]: when set, fwdone[1:0] set pscomplete[1:0]
    // 1. fw_wr[0] is generated in uram_event_buffer -> clears pscomplete[0]
    // 2. mark A sets ps_fwupdate_gpo[0]
    // 3. fw_wr[1] is generated in uram_event_buffer -> clears pscomplete[1]
    // 4. mark B sets ps_fwupdate_gpo[1]
    // 5. fwdone[0] with ps_fwupdate_gpo[0] sets pscomplete[0]
    // 6. fwdone[1] with ps_fwupdate_gpo[1] sets pscomplete[1]    
        
    wire [1:0] clear_pscomplete_wbclk;
    // these are in ifclk
    flag_sync u_clear_pscomplete0(.in_clkA(fw_wr_i[0]), .out_clkB(clear_pscomplete_wbclk[0]),
                                 .clkA(ifclk_i),.clkB(wb_clk_i));
    flag_sync u_clear_pscomplete1(.in_clkA(fw_wr_i[1]), .out_clkB(clear_pscomplete_wbclk[1]),
                                  .clkA(ifclk_i),.clkB(wb_clk_i));

    reg [1:0] firmware_block_marked = {2{1'b0}};
    reg [1:0] firmware_block_done = {2{1'b0}};

    (* CUSTOM_CC_DST = "SYSREFCLK", ASYNC_REG = "TRUE" *)
    reg fw_dlm_sync_sysclk = 0;
    reg fw_downloadmode_sysclk = 0;
    
    reg [2:0] ps_fwdone0_wbclk = {2{1'b0}};
    reg [2:0] ps_fwdone1_wbclk = {2{1'b0}};

    reg [2:0] ps_fwdone0_sysclk = {2{1'b0}};
    reg [2:0] ps_fwdone1_sysclk = {2{1'b0}};
    

    always @(posedge sysclk_i) begin
        fw_dlm_sync_sysclk <= fw_downloadmode_i;
        fw_downloadmode_sysclk <= fw_dlm_sync_sysclk;
        
        ps_fwdone0_sysclk <= { ps_fwdone0_sysclk[1:0], ps_fwdone_gpi_i[0] };
        ps_fwdone1_sysclk <= { ps_fwdone1_sysclk[1:0], ps_fwdone_gpi_i[1] };
                
        if (!fw_downloadmode_sysclk) firmware_block_marked[0] <= 0;
        else if (fw_mark_i[0]) firmware_block_marked[0] <= 1;
        else if (ps_fwdone0_sysclk[2:1] == 2'b01) firmware_block_marked[0] <= 0;        
        
        if (!fw_downloadmode_sysclk) firmware_block_marked[1] <= 0;
        else if (fw_mark_i[1]) firmware_block_marked[1] <= 1;
        else if (ps_fwdone1_sysclk[2:1] == 2'b01) firmware_block_marked[1] <= 0;
    end
    
    always @(posedge wb_clk_i) begin
        ps_fwdone0_wbclk <= { ps_fwdone0_wbclk[1:0], ps_fwdone_gpi_i[0] };
        ps_fwdone1_wbclk <= { ps_fwdone1_wbclk[1:0], ps_fwdone_gpi_i[1] };
        
        // calling this 'firmware block done' is misleading, it's actually
        // 'firmware block is ready for new data'
        if (!fw_downloadmode_i) firmware_block_done[0] <= 0;
        else if (ps_fwdone0_wbclk[2:1] == 2'b01) firmware_block_done[0] <= 1;
        else if (clear_pscomplete_wbclk[0]) firmware_block_done[0] <= 0;
        
        if (!fw_downloadmode_i) firmware_block_done[1] <= 0;
        else if (ps_fwdone1_wbclk[2:1] == 2'b01) firmware_block_done[1] <= 1;
        else if (clear_pscomplete_wbclk[1]) firmware_block_done[1] <= 0;
    end
    
    assign fw_pscomplete_o = firmware_block_done;
    assign ps_fwupdate_gpo_o = firmware_block_marked;
        
endmodule
