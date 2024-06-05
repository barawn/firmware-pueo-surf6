`timescale 1ns / 1ps
// COMMAND DECODER
module pueo_command_decoder(
        input sysclk_i,
        input [31:0] command_i,
        input        command_valid_i,
        // Bit commands
        output       cmdsync_o,
        output       cmdpps_o,
        output       cmdproc_rst_o,
        // Command processor output
        output [7:0] cmdproc_tdata,
        output       cmdproc_tvalid,
        output       cmdproc_tlast,
        // NOTE NOTE NOTE THIS IS EFFING IGNORED
        input        cmdproc_tready,
        // trigger output
        output [14:0] trig_time_o,
        output        trig_valid_o
    );
    
    // TURFIOs can just hard-case this. Everyone else gets it assigned.
    localparam [3:0] CMDPROC_ADDR = 4'b0000;
    localparam [3:0] CMDPROC_BROADCAST = 4'b1111;
    wire cmdproc_selected = ( command_i[24 +: 4] == CMDPROC_ADDR ||
                              command_i[24 +: 4] == CMDPROC_BROADCAST );
    
    // Just treat these as combinatoric and see how we do.
    assign trig_valid_o = command_i[15] && command_valid_i;
    assign trig_time_o = command_i[0 +: 14];
    
    // These are a bit nastier, we'll see.
    assign cmdproc_tdata = command_i[16 +: 8];
    assign cmdproc_tvalid = (command_i[28 +: 4] == 4'b0001 ||
                             command_i[28 +: 4] == 4'b0101) && command_valid_i && cmdproc_selected;
    assign cmdproc_tlast = command_i[30];                            
    
    wire bit_command = command_valid_i && command_i[28 +: 4] == 4'b0000;
    assign cmdsync_o = bit_command && command_i[16];
    assign cmdpps_o = bit_command && command_i[17];
    assign cmdproc_rst_o = bit_command && command_i[18];
    
endmodule
