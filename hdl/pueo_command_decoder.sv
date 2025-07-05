`timescale 1ns / 1ps
// COMMAND DECODER
//
// Command decoding happens at 375 MHz, but obviously it's only
// captured every 125 MHz and the data valid only occurs every
// 15.625 MHz. So we need to track things here.
//
// The capture in rxclk_x3 happens when rxclk_ce_i goes 
module pueo_command_decoder(
        input sysclk_i,
        input [31:0] command_i,
        input        command_valid_i,
        
        // this lets software know that a sync was seen.
        input        wb_clk_i,
        output       rundo_sync_wbclk_o,        
        // this lets software know that a NOOP_LIVE was seen.
        output       runnoop_live_wbclk_o,
        
        // Run commands. All of these are multicycle!
        output       rundo_sync_o,
        output       runrst_o,
        output       runstop_o,
        // PPS
        output       pps_o,
        // and mode1 controls
        output       cmdproc_rst_o,
        output [7:0] cmdproc_tdata,
        output       cmdproc_tvalid,
        output       cmdproc_tlast,
        // NOTE NOTE NOTE THIS IS EFFING IGNORED
        input        cmdproc_tready,
        // upgrade data
        output [7:0] fw_tdata,
        output       fw_tvalid,
        // NOTE NOTE NOTE THIS IS EFFING IGNORED
        input        fw_tready,
        // the mark output allows us to set the GPI to the CPU.
        // it's sent inline with the data so nothing can race.
        output [1:0] fw_mark_o,
        // trigger output
        output [14:0] trig_time_o,
        output        trig_valid_o
    );

    parameter DEBUG = "TRUE";

    // We simplified the heck out of this.
    assign trig_valid_o = command_i[15] && command_valid_i;
    assign trig_time_o = command_i[0 +: 15];

    // message stuff
    wire   message_valid = !command_i[31] && command_valid_i;
    // used to stretch fw_valid being set.
    // because it is set by command_valid_i (1st clock in period)
    // and then cleared 2 clocks later, its period looks like
    // aclk:   --__--__--__--__
    // valid:  ----____________
    // rrg0:   ____----________
    // rrg1:   ________----____
    // fwvld:  ____--------____
    // ifclk:  ------______----
    // meaning it has setup = 5.333 ns and hold = 0 ns
    reg [1:0] message_valid_rereg = {2{1'b0}};
    
    // Mode1
    wire [1:0] mode1type = command_i[24 +: 2];
    // has setup = 5.333 ns and gigantic hold, but just make it -2.667 for fun
    wire [7:0] mode1data = command_i[16 +: 8];
    localparam [1:0] MODE1TYPE_SPECIAL = 2'b00;
    localparam [1:0] MODE1TYPE_NORMAL = 2'b01;
    localparam [1:0] MODE1TYPE_LAST = 2'b11;
    localparam [1:0] MODE1TYPE_FW = 2'b11;
    // N.B.: MODE1SPECIAL_RESET also kicks us out of training.
    localparam [7:0] MODE1SPECIAL_RESET = 8'h01;
    localparam [7:0] MODE1SPECIAL_FW_MARK_A = 8'h02;
    localparam [7:0] MODE1SPECIAL_FW_MARK_B = 8'h03;

    reg mode1_rst = 0;
    (* CUSTOM_MC_SRC_TAG = "FW_DATA", CUSTOM_MC_MIN = "-1.0", CUSTOM_MC_MAX = "2.0" *)
    reg [7:0] mode1_tdata = {8{1'b0}};
    reg mode1_tvalid = 0;
    reg mode1_tlast = 0;
    (* CUSTOM_MC_SRC_TAG = "FW_VALID", CUSTOM_MC_MIN = "0", CUSTOM_MC_MAX = "2.0" *)
    reg firmware_valid = 0;
    
    
    // Runcmd
    wire [1:0] runcmd = command_i[26 +: 2];
    localparam [1:0] RUNCMD_NOOP_LIVE = 2'b00;
    localparam [1:0] RUNCMD_DO_SYNC = 2'b01;
    localparam [1:0] RUNCMD_RESET = 2'b10;
    localparam [1:0] RUNCMD_STOP = 2'b11;
    // Everything I was doing before was garbage.
    // These all need to be multicycle for exactly the same reason the FWU
    // stuff needs to be.
    // command_valid_i goes high in ACLK phase 0, so when qualified,
    // this is ACLK phase 1. It's then cleared in ACLK phase 2.
    // So all same as FWU.
    (* CUSTOM_MC_SRC_TAG = "RUNDO_SYNC", CUSTOM_MC_MIN = "0", CUSTOM_MC_MAX = "2.0" *)     
    reg do_rundo_sync = 0;
    (* CUSTOM_MC_SRC_TAG = "RUNRST", CUSTOM_MC_MIN = "0", CUSTOM_MC_MAX = "2.0" *) 
    reg do_runrst = 0;
    (* CUSTOM_MC_SRC_TAG = "RUNSTOP", CUSTOM_MC_MIN = "0", CUSTOM_MC_MAX = "2.0" *)
    reg do_runstop = 0;
    // this is a flag that a valid NOOP_LIVE was seen. It'll go a bunch, who cares.
    reg do_live = 0;
    flag_sync u_do_live_sync(.in_clkA(do_live),.out_clkB(runnoop_live_wbclk_o),
                             .clkA(sysclk_i), .clkB(wb_clk_i));

    // this is a flag for informing wb_clk
    reg sync_flag = 0;
    flag_sync u_do_sync_sync(.in_clkA(sync_flag),.out_clkB(rundo_sync_wbclk_o),
                             .clkA(sysclk_i), .clkB(wb_clk_i));

    reg pps = 0;
    
    reg fw_mark_a = 0;
    reg fw_mark_b = 0;
    
    always @(posedge sysclk_i) begin
        message_valid_rereg <= {message_valid_rereg[0], message_valid};
        // These are statically captured.
        if (message_valid) begin
            mode1_tdata <= mode1data;
            mode1_tlast <= (mode1type == MODE1TYPE_LAST);            
        end            

        do_live <= (message_valid && runcmd == RUNCMD_NOOP_LIVE);

        if (message_valid && runcmd == RUNCMD_DO_SYNC) do_rundo_sync <= 1;
        else if (message_valid_rereg[1]) do_rundo_sync <= 0;
        
        if (message_valid && runcmd == RUNCMD_RESET) do_runrst <= 1;
        else if (message_valid_rereg[1]) do_runrst <= 0;
        
        if (message_valid && runcmd == RUNCMD_STOP) do_runstop <= 1;
        else if (message_valid_rereg[1]) do_runstop <= 0;
        
        sync_flag <= (message_valid && runcmd == RUNCMD_DO_SYNC);
        
        mode1_rst <= (mode1type == MODE1TYPE_SPECIAL) && (mode1data == MODE1SPECIAL_RESET) && message_valid;
        // stretch firmware_valid. mode1_tdata is naturally stretched.
        if (message_valid_rereg[1]) firmware_valid <= 1'b0;
        else if (message_valid) firmware_valid <= (mode1type == MODE1TYPE_FW);

        mode1_tvalid <= (mode1type == MODE1TYPE_NORMAL || mode1type == MODE1TYPE_LAST) && message_valid;

        fw_mark_a <= (mode1type == MODE1TYPE_SPECIAL) && (mode1data == MODE1SPECIAL_FW_MARK_A) && message_valid;
        fw_mark_b <= (mode1type == MODE1TYPE_SPECIAL) && (mode1data == MODE1SPECIAL_FW_MARK_B) && message_valid;       
    end
    assign cmdproc_tdata = mode1_tdata;
    assign cmdproc_tvalid = mode1_tvalid;
    assign cmdproc_tlast = mode1_tlast;
    assign cmdproc_rst_o = mode1_rst;
    
    assign fw_tdata = mode1_tdata;
    assign fw_tvalid = firmware_valid;
    assign fw_mark_o = {fw_mark_b, fw_mark_a};
    
    assign rundo_sync_o = do_rundo_sync;
    assign runrst_o = do_runrst;
    assign runstop_o = do_runstop;
endmodule
