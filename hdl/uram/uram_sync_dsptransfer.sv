`timescale 1ns / 1ps
`include "dsp_macros.vh"
// This module replaces the sync transfer, because I think
// it was driving a fair amount of power and timing, and I don't
// think it's necessary: the DSPs wide muxes will do the job fine.
// A lot of the benefit is that there's no fanout of the write
// phase - it just goes two places now.
//
// This however takes *two* channel inputs, and it anchors
// locations a bit more. We'll see.
module uram_sync_dsptransfer #(
        parameter NSAMP=8,
        parameter NBIT=12,
        parameter SCRAMBLE_OPT = "TRUE"
    )(
        input aclk_i,
        input aclk_sync_i,
        input memclk_i,
        input memclk_sync_i,
        input [NSAMP*NBIT-1:0] datA_i,
        output [(NSAMP*3/4)*NBIT-1:0] datA_o,   // 72 bits
        input [NSAMP*NBIT-1:0] datB_i,
        output [(NSAMP*3/4)*NBIT-1:0] datB_o    // 72 bits
    );
    
    localparam NSAMP_A_TOP = (NSAMP*3/4);
    localparam NSAMP_A_BOT = (NSAMP*1/4);
    localparam NSAMP_B_TOP = (NSAMP*1/4);
    localparam NSAMP_B_BOT = (NSAMP*3/4);
    localparam NSAMP_C_TOP = (NSAMP*2/4);
    localparam NSAMP_C_BOT = (NSAMP*2/4);
    
    localparam NSAMP_MEM = (NSAMP*3/4);    
    
    localparam NCHAN = 2;
    localparam NPHASE = 4;
    localparam NDSP = 3;
    
    // Sync transfer stuff.
    wire [NCHAN-1:0][NSAMP*NBIT-1:0] dat_i;
    assign dat_i[0] = datA_i;
    assign dat_i[1] = datB_i;
    // atop: min -3*tick=-2 ns = -0.75, max 9*tick = 6 ns =2.25
    (* CUSTOM_MC_SRC_TAG = "ATOP_XFER", CUSTOM_MC_MIN = "-0.75", CUSTOM_MC_MAX = "2.25" *)
    reg [NCHAN-1:0][NBIT*(NSAMP_A_TOP)-1:0] bufferA_top = {NCHAN*NBIT*NSAMP_A_TOP{1'b0}};
    // abot: min -6*tick=4ns=1.5, max 6*tick = 4ns = 1.5
    (* CUSTOM_MC_SRC_TAG = "ABOT_XFER", CUSTOM_MC_MIN = "-1.5", CUSTOM_MC_MAX = "1.5" *)
    reg [NCHAN-1:0][NBIT*(NSAMP_A_BOT)-1:0] bufferA_bot = {NCHAN*NBIT*NSAMP_A_BOT{1'b0}};
    // btop -1, 11: min -0.6667 ns = -0.25, max 11=7.333=2.75
    (* CUSTOM_MC_SRC_TAG = "BTOP_XFER", CUSTOM_MC_MIN = "-0.25", CUSTOM_MC_MAX = "2.75" *)
    reg [NCHAN-1:0][NBIT*(NSAMP_B_TOP)-1:0] bufferB_top = {NCHAN*NBIT*NSAMP_B_TOP{1'b0}};
    // bbot -4=-2.667 ns =-1, max 8 = 5.333 = 2
    (* CUSTOM_MC_SRC_TAG = "BBOT_XFER", CUSTOM_MC_MIN = "-1", CUSTOM_MC_MAX = "2" *)
    reg [NCHAN-1:0][NBIT*(NSAMP_B_BOT)-1:0] bufferB_bot = {NCHAN*NBIT*NSAMP_B_BOT{1'b0}};
    // third aclk buffer
    // ctop = -2 (-1.333 ns=-0.5), 10 (6.667=2.5)
    (* CUSTOM_MC_SRC_TAG = "CTOP_XFER", CUSTOM_MC_MIN = "-0.5", CUSTOM_MC_MAX = "2.5" *)
    reg [NCHAN-1:0][NBIT*(NSAMP_C_TOP)-1:0] bufferC_top = {NCHAN*NBIT*NSAMP_C_TOP{1'b0}};
    // cbot -5 (-3.333 ns = -1.25), 7 (4.667 ns = 1.75)
    (* CUSTOM_MC_SRC_TAG = "CBOT_XFER", CUSTOM_MC_MIN = "-1.25", CUSTOM_MC_MAX = "1.75" *)
    reg [NCHAN-1:0][NBIT*(NSAMP_C_BOT)-1:0] bufferC_bot = {NCHAN*NBIT*NSAMP_C_BOT{1'b0}};
    
    // indicates what phase of the memclk we're in. One hot.
    reg [3:0] write_phase = {4{1'b0}};
    // indicates what phase of the aclk we're in. One hot.
    reg [2:0] buffer_phase = {3{1'b0}};
    
    // Buffer phase track.
    always @(posedge aclk_i) begin
        if (aclk_sync_i) buffer_phase <= 3'b010;
        else buffer_phase <= { buffer_phase[1:0], buffer_phase[2] };
    end
               
    // It takes a fair number of DSPs to do the muxing like this, so we'll have to see if this is
    // better or not. There are 6 samples of 12 bits in memclk, and they can be sourced from any
    // one of 4 places. 4 inputs means we need 2 DSPs, 6 possible samples at 12 bits means we need 1.5x
    // So using 2 channels, this is 6 total DSPs.
    
    // The ONLY registers that the DSPs have are the PREG. The inputs all come from aclk, but they
    // have multicycle paths to the PREG with plenty of timing.
    
    // Our DSPs (A/B/C/D/E/F) are arranged
    //
    // write_data_in[2], write_data_in[3]   dspF     -> PREG -> datB[5:2]
    // write_data_in[0], write_data_in[1]   dspE
    // write_data_in[2], write_data_in[3]   dspD     -> PREG -> datB[1:0],datA[5:4]
    // write_data_in[0], write_data_in[1]   dspC
    // write_data_in[2], write_data_in[3]   dspB     -> PREG -> datA[3:0]
    // write_data_in[0], write_data_in[1]   dspA
    
    // the configuration we want is:
    // phase    low opmode  high opmode
    // 0        X_OPMODE_AB Z_OPMODE_PCIN
    // 1        Y_OPMODE_C  Z_OPMODE_PCIN
    // 2        Y_OPMODE_C  X_OPMODE_AB
    // 3        Y_OPMODE_C  Y_OPMODE_C
    
    // These WOULD map to: { phase3, phase2, phase0 or phase 1 }
    // and                 { phase1 or phase 2 or phase 3, phase 0 }
    // BUT because they're registered at the DSP, they're off by 1, so it's
    //                     { phase2, phase1, phase 3 or phase 1 }
    //                     { phase0 or phase 1 or phase 2, phase 3 }
    // Sequentially they need to go
    // phase    high opmode low opmode
    // 0        001         10
    // 1        001         10
    // 2        010         10
    // 3        100         01
    // Expanding these sequences with dummy bits we have
    // phase    high opmode low opmode
    // 0        0001        0010
    // 1        1001        0110
    // 2        0010        1010
    // 3        0100        0001
    (* KEEP = "TRUE" *)
    reg [3:0] high_opmode_sel = 4'b0001;
    (* KEEP = "TRUE" *)
    reg [3:0] low_opmode_sel = 4'b0010;
    
    always @(posedge memclk_i) begin
        if (memclk_sync_i) high_opmode_sel <= 4'b1001;
        else begin
            case (high_opmode_sel)
                4'b0001: high_opmode_sel <= 4'b1001;
                4'b1001: high_opmode_sel <= 4'b0010;
                4'b0010: high_opmode_sel <= 4'b0100;
                4'b0100: high_opmode_sel <= 4'b0001;
                default: high_opmode_sel <= 4'b1001;
            endcase              
        end
        if (memclk_sync_i) low_opmode_sel <= 4'b0110;
        else begin
            case (low_opmode_sel)
                4'b0010: low_opmode_sel <= 4'b0110;
                4'b0110: low_opmode_sel <= 4'b1010;
                4'b1010: low_opmode_sel <= 4'b0001;
                4'b0001: low_opmode_sel <= 4'b0010;
                default: low_opmode_sel <= 4'b0110;
            endcase
        end        
    end
    
// This is the overall logic:
//    always @(posedge memclk_i) begin
//        if (memclk_sync_i) write_phase <= 4'b0010;
//        else write_phase <= { write_phase[2:0], write_phase[3] };
//    end
// memclk_sync_i pushes us into phase 1, so         
        
    wire [8:0] dsphigh_OPMODE = { 2'b00,
                                  2'b00, high_opmode_sel[0],
                                  high_opmode_sel[1], high_opmode_sel[1],
                                  high_opmode_sel[2], high_opmode_sel[2] };
    wire [8:0] dsplow_OPMODE = { 2'b00,
                                 3'b000,
                                 low_opmode_sel[1], low_opmode_sel[1],
                                 low_opmode_sel[0], low_opmode_sel[0] };

    // write_data_in[ch][ph] is a 72-bit object.
    // and then we merge them into a 144-bit object which is 3x48 and distribute it between the three high/low
    wire [NCHAN-1:0][NPHASE-1:0][NSAMP_MEM*NBIT-1:0] write_data_in;
    // after the scramble opt
    wire [NCHAN-1:0][NPHASE-1:0][NSAMP_MEM*NBIT-1:0] write_data_in_opt;
    // merged
    wire [NPHASE-1:0][NCHAN*NSAMP_MEM*NBIT-1:0] write_data_in_full;
    assign write_data_in_full[0] = { write_data_in_opt[1][0],
                                     write_data_in_opt[0][0] };
    assign write_data_in_full[1] = { write_data_in_opt[1][1],
                                     write_data_in_opt[0][1] };
    assign write_data_in_full[2] = { write_data_in_opt[1][2],
                                     write_data_in_opt[0][2] };
    assign write_data_in_full[3] = { write_data_in_opt[1][3],
                                     write_data_in_opt[0][3] };
    // these can be assigned in a loop as
    // assign dsp_inputs[i][j] = write_data_in_full[j][48*i +: 48];
    wire [NDSP-1:0][NPHASE-1:0][47:0] dsp_inputs;
    wire [NDSP-1:0][47:0] dsp_outputs;

    assign datA_o[0 +: 48] = dsp_outputs[0];
    assign datA_o[48 +: 24] = dsp_outputs[1][0 +: 24];
    assign datB_o[0 +: 24] = dsp_outputs[1][24 +: 24];
    assign datB_o[24 +: 48] = dsp_outputs[2];

    // The loop issue we have is that sometimes we want to loop over phases,
    // sometimes we want to loop over DSPs. If we have an outer phase loop
    // we can do more, but we still need a third variable for instantiating
    // the DSPs.
    function [NSAMP_MEM*NBIT-1:0] scramble_map;
        input [NSAMP_MEM*NBIT-1:0] unscr;
        input integer phase;
        begin
            // scramble opt swaps groups 24 bits at a time
            // for 0 it goes 2, 0, 1
            // for 1 it goes 0, 1, 2
            // for 2 it goes 1, 0, 2
            // for 3 it goes 2, 1, 0            
            if (phase == 0)
                scramble_map = { unscr[71:48], unscr[23:0], unscr[47:24] };
            else if (phase == 1)
                scramble_map = { unscr[23:0], unscr[47:24], unscr[71:48] };
            else if (phase == 2)
                scramble_map = { unscr[47:24], unscr[23:0], unscr[71:48] };
            else
                scramble_map = unscr;
        end
    endfunction

    function [NSAMP_MEM*NBIT-1:0] buffer_map;
        input [NSAMP_A_TOP*NBIT-1:0] A_top;
        input [NSAMP_A_BOT*NBIT-1:0] A_bot;
        input [NSAMP_B_TOP*NBIT-1:0] B_top;
        input [NSAMP_B_BOT*NBIT-1:0] B_bot;
        input [NSAMP_C_TOP*NBIT-1:0] C_top;
        input [NSAMP_C_BOT*NBIT-1:0] C_bot;
        input integer phase;
        begin
            if (phase == 0)
                buffer_map = { C_bot, B_top };
            else if (phase == 1)
                buffer_map = { A_bot, C_top };
            else if (phase == 2)
                buffer_map = A_top;
            else
                buffer_map = B_bot;
        end
    endfunction
    
    // this is so goofy
    generate
        genvar ch, chp, d, dp;
        for (ch=0;ch<NCHAN;ch=ch+1) begin : C
            always @(posedge aclk_i) begin : CB
                if (buffer_phase[0]) begin
                    bufferB_bot[ch] <= dat_i[ch][0 +: NBIT*NSAMP_B_BOT];
                    bufferB_top[ch] <= dat_i[ch][NBIT*NSAMP_B_BOT +: NBIT*NSAMP_B_TOP];
                end        
                if (buffer_phase[1]) begin
                    bufferC_bot[ch] <= dat_i[ch][0 +: NBIT*NSAMP_C_BOT];
                    bufferC_top[ch] <= dat_i[ch][NBIT*NSAMP_C_BOT +: NBIT*NSAMP_C_TOP];
                end
                if (buffer_phase[2]) begin
                    bufferA_bot[ch] <= dat_i[ch][0 +: NBIT*NSAMP_A_BOT];
                    bufferA_top[ch] <= dat_i[ch][NBIT*NSAMP_A_BOT +: NBIT*NSAMP_A_TOP];
                end                                
            end
            for (chp=0;chp<NPHASE;chp=chp+1) begin : P
                assign write_data_in[ch][chp] = buffer_map(bufferA_top[ch],
                                                           bufferA_bot[ch],
                                                           bufferB_top[ch],
                                                           bufferB_bot[ch],
                                                           bufferC_top[ch],
                                                           bufferC_bot[ch],
                                                           chp);
                if (SCRAMBLE_OPT == "TRUE") begin : SCR
                    assign write_data_in_opt[ch][chp] = scramble_map(write_data_in[ch][chp],chp);
                end else begin : NSCR
                    assign write_data_in_opt[ch][chp] =write_data_in[ch][chp];
                end
            end
        end            
        for (d=0;d<NDSP;d=d+1) begin : MUX
            for (dp=0;dp<NPHASE;dp=dp+1) begin : MUXP
                assign dsp_inputs[d][dp] = write_data_in_full[dp][48*d +: 48];            
            end
            wire [47:0] dsplow_AB = dsp_inputs[d][0];
            wire [47:0] dsplow_C = dsp_inputs[d][1];
            wire [47:0] dsphigh_AB = dsp_inputs[d][2];
            wire [47:0] dsphigh_C = dsp_inputs[d][3];
            wire [47:0] dsp_cascade;
            
            (* CUSTOM_MC_DST_TAG = "ATOP_XFER ABOT_XFER BTOP_XFER BBOT_XFER CTOP_XFER CBOT_XFER" *)
            DSP48E2 #(.OPMODEREG(1),
                      .ALUMODEREG(0),
                      .CARRYINSELREG(0),
                      .INMODEREG(0),
                      `DE2_UNUSED_ATTRS,
                      `NO_MULT_ATTRS,
                      .AREG(0),.BREG(0),.CREG(0),.PREG(0))
                      u_dsplow(.CLK(memclk_i),
                               .A(`DSP_AB_A(dsplow_AB)),
                               .B(`DSP_AB_B(dsplow_AB)),
                               .C(dsplow_C),
                               .OPMODE(dsplow_OPMODE),
                               .CARRYIN(1'b0),
                               .CARRYINSEL(`CARRYINSEL_CARRYIN),
                               .ALUMODE(`ALUMODE_SUM_ZXYCIN),
                               .CECTRL(1'b1),
                               .PCOUT(dsp_cascade));
            (* CUSTOM_MC_DST_TAG = "ATOP_XFER ABOT_XFER BTOP_XFER BBOT_XFER CTOP_XFER CBOT_XFER" *)
            DSP48E2 #(.OPMODEREG(1),
                      .ALUMODEREG(0),
                      .CARRYINSELREG(0),
                      .INMODEREG(0),
                      `DE2_UNUSED_ATTRS,
                      `NO_MULT_ATTRS,
                      .AREG(0),.BREG(0),.CREG(0),.PREG(1))
                      u_dsphigh(.CLK(memclk_i),
                                .A(`DSP_AB_A(dsphigh_AB)),
                                .B(`DSP_AB_B(dsphigh_AB)),
                                .C(dsphigh_C),
                                .OPMODE(dsphigh_OPMODE),
                                .ALUMODE(`ALUMODE_SUM_ZXYCIN),
                                .CARRYINSEL(`CARRYINSEL_CARRYIN),
                                .CARRYIN(1'b0),
                                .CECTRL(1'b1),
                                .CEP(1'b1),
                                .PCIN(dsp_cascade),
                                .P(dsp_outputs[d]));                                
        end
    endgenerate        
                                     
endmodule
