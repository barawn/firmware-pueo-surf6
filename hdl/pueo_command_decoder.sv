`timescale 1ns / 1ps
// COMMAND DECODER
module pueo_command_decoder(
        input sysclk_i,
        input [31:0] command_i,
        input        command_valid_i,
        // Run commands
        output       rundosync_o,
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
        // trigger output
        output [14:0] trig_time_o,
        output        trig_valid_o
    );

    // We simplified the heck out of this.
    assign trig_valid_o = command_i[15] && command_valid_i;
    assign trig_time_o = command_i[0 +: 14];

    // message stuff
    wire   message_valid = !command_i[31] && command_valid_i;
    
    // Mode1
    wire [1:0] mode1type = command_i[24 +: 2];
    wire [7:0] mode1data = command_i[16 +: 8];
    localparam [1:0] MODE1TYPE_SPECIAL = 2'b00;
    localparam [1:0] MODE1TYPE_NORMAL = 2'b01;
    localparam [1:0] MODE1TYPE_LAST = 2'b11;
    localparam [1:0] MODE1TYPE_FW = 2'b11;
    localparam [7:0] MODE1SPECIAL_RESET = 8'h01;

    reg mode1_rst = 0;
    reg [7:0] mode1_tdata = {8{1'b0}};
    reg mode1_tvalid = 0;
    reg mode1_tlast = 0;
    // fw
    reg firmware_valid = 0;
    
    
    // Runcmd
    wire [1:0] runcmd = command_i[26 +: 2];
    localparam [1:0] RUNCMD_NO_OP = 2'b00;
    localparam [1:0] RUNCMD_DO_SYNC = 2'b01;
    localparam [1:0] RUNCMD_RESET = 2'b10;
    localparam [1:0] RUNCMD_STOP = 2'b11;
    // Note that these go into a programmable SYSCLK delay,
    // so the 1 clock offset here doesn't matter.
    reg run_do_sync = 0;
    reg run_rst = 0;    
    // run_stop's timing doesn't matter
    reg run_stop = 0;

    reg pps = 0;
    
    always @(posedge sysclk_i) begin
        // These are statically captured.
        if (message_valid) begin
            mode1_tdata <= mode1data;
            mode1_tlast <= (mode1type == MODE1TYPE_LAST);            
        end            
        // These are flags
        run_do_sync <= (runcmd == RUNCMD_DO_SYNC) && message_valid;
        run_rst <= (runcmd == RUNCMD_RESET) && message_valid;
        run_stop <= (runcmd == RUNCMD_STOP) && message_valid;
        mode1_rst <= (mode1type == MODE1TYPE_SPECIAL) && (mode1data == MODE1SPECIAL_RESET) && message_valid;
        firmware_valid <= (mode1type == MODE1TYPE_FW) && message_valid;
        mode1_tvalid <= (mode1type == MODE1TYPE_NORMAL || mode1type == MODE1TYPE_LAST) && message_valid;

        
    end
    assign cmdproc_tdata = mode1_tdata;
    assign cmdproc_tvalid = mode1_tvalid;
    assign cmdproc_tlast = mode1_tlast;
    assign cmdproc_rst_o = mode1_rst;
    
    assign fw_tdata = mode1_tdata;
    assign fw_tvalid = firmware_valid;
    
    assign rundosync_o = run_do_sync;
    assign runrst_o = run_rst;
endmodule
