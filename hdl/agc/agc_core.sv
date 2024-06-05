`timescale 1ns / 1ps
// PER-CHANNEL AGC PORTION
// This module contains *ONLY* -
// 1) the DSPs for rescaling the inputs and the stuff to saturate/abs things
// 2) the square/probit accumulators + LFSR muxes
// The measurement and parameter stuff is elsewhere, since they're common.
// The LFSR portion isn't common because it's so small that it's easier
// to just duplicate it locally.
module agc_core #(parameter NBITS=12, 
                  parameter NSAMP=8,
                  parameter OBITS=5,
                  parameter SQ_BITS=24,
                  parameter PR_BITS=21,
                  parameter CLKTYPE="NONE")(
        input clk_i,
        // data inputs
        input [NBITS*NSAMP-1:0] rf_dat_i,
        // rescaled outputs
        output [OBITS*NSAMP-1:0] rf_dat_o,
        // square accumulators
        output [SQ_BITS-1:0] sq_accum_o,
        // probit accumulators
        output [PR_BITS-1:0] gt_accum_o,
        output [PR_BITS-1:0] lt_accum_o,        
        
        // Begin AGC cycle (resets accumulators)
        input agc_tick_i,
        // AGC clock enable, for running the accumulators
        input agc_ce_i,
        // AGC reset, kills the LFSR to resync it
        input agc_rst_i,
        // Gain scale
        input [16:0] agc_scale_i,
        // Offset
        input [7:0] offset_i,
        // Loads the new scale
        input agc_scale_ce_i,
        // Loads the new offset
        input agc_offset_ce_i,
        // Applies both
        input agc_apply_i
    );


    // less than/greater than thresholds for probit/DC offset
    wire [NSAMP-1:0] lt_thresh;
    wire [NSAMP-1:0] gt_thresh;
    // absolute values for RMS accumulators before the mux
    wire [(OBITS-1)*NSAMP-1:0] abs_vals;
    // absolute value for RMS *after* mux
    wire [OBITS-2:0] abs_val_mux;
    // Reset value for square accumulator
    localparam [23:0] SQ_OFFSET = 16384;
    
    // probit accumulator
    probit_accumulator #(.NBITS(PR_BITS),
                         .CLKTYPE(CLKTYPE))
        u_pr(.clk_i(clk_i),
             .ce_i(agc_ce_i),
             .rst_i(agc_tick_i),
             .gt_i(gt_thresh),
             .lt_i(gt_thresh),
             .gt_sum_o(gt_accum_o),
             .lt_sum_o(lt_accum_o));
    
    // only apply the sync if we haven't synced before
    reg lfsr_synced = 0;
    reg lfsr_sync = 0;
    always @(posedge clk_i) begin
        if (agc_rst_i) lfsr_synced <= 1'b0;
        else if (lfsr_sync) lfsr_synced <= 1'b1;
        
        lfsr_sync <= agc_tick_i && !lfsr_synced;
    end
    // abs mux
    lfsr_rms_mux u_mux(.clk_i(clk_i),
                       .sync_i(lfsr_sync),
                       .rst_i(agc_rst_i),
                       .in_i(abs_vals),
                       .out_o(abs_val_mux));                     
    // square accumulator             
    square_5bit_accumulator #(.NBITS(SQ_BITS),
                              .RESET_VALUE(SQ_OFFSET),
                              .CLKTYPE(CLKTYPE))
       u_sq(.clk_i(clk_i),
            .in_i(abs_val_mux),
            .ce_i(agc_ce_i),
            .rst_i(agc_tick_i),
            .accum_o(sq_accum_o));                                      
    
    generate
        genvar i;
        for (i=0;i<NSAMP;i=i+1) begin : DSPS
            agc_dsp u_dsp( .clk_i(clk_i),
                           .dat_i(rf_dat_i[NBITS*i +: NBITS]),
                           .scale_i(agc_scale_i),
                           .offset_i(agc_offset_i),
                           .ce_scale_i(agc_scale_ce_i),
                           .ce_offset_i(agc_offset_ce_i),
                           .apply_i(agc_apply_i),
                           .out_o(rf_dat_o[OBITS*i +: OBITS]),
                           .abs_o(abs_vals[(OBITS-1)*i +: (OBITS-1)]),
                           .gt_o(gt_thresh[i]),
                           .lt_o(lt_thresh[i]));
        end
    endgenerate            

// OLD STUFF

//    // this is now (8*sq). to get mean, we divide by 8, then by 2^17.
//    // this means this is now 2^20 times RMS. so when we take the square root,
//    // it is now 2^10 times RMS. note that this means this is Q2.10, which is
//    // exactly what you would expect given that the RMS cannot reach 4.
//    wire rms_done;
//    wire [11:0] rms;
//    // and now we calculate the reciprocal to 22 bits.
//    // We have to do it this large because we're in
//    // Q2.10 format (value * 1024). Computing to, say, 16 bits
//    // would give scale * (65536/1024) = scale * 64
//    // since our *nominal* here is "1", that means our resolution
//    // wouldn't be great (1/64th scale). Nominally we want something
//    // with about 12 bits of range, so we need another 6 bits.
    
//    // for instance if we have 131072 samples of "4", the square accum gives
//    // 1,310,720
//    // then the offset gives
//    // 1,327,104 divided by 2^20 = 1.2652625
//    // the square root gives
//    // 1152 divided by 1024 = 1.2652625
//    // reciprocal would give (4,194,304/1152) = 3641
//    // implying scale is (3641/4096) = ~0.88892 (it's actually 8/9ths since input was 9/8ths)
//    // We can drop a large number of these bits though, since the reciprocal thinks the
//    // input can go down all the way to zero, and it can't. Its minimum value is 16384,
//    // so the minimum RMS is 128, so the maximum scale is 32768 (14 bits).
//    // So bits [19:16] are manifestly zero and aren't tracked.
//    // Note that the maximum value in the accumulator is 16384 + 131072*120 = 15,745,024
//    // out of sqrt is 3968
//    // reciprocal gives 1057 (scale ~ 0.2580)
//    // So our RMS range varies from 1057 - 32768
//    // with a scaling of 1/4096
//    // Converting probit scaling to actual scale is basically (probit/3072) plus an offset
//    // So for instance if we measure an RMS of 0.5 (scale 2 = 8192) we get 7923 probit
//    // scale RMS - target scale = (8192 - 4096) = 4096
//    // scale probit - target probit = (7923 - 4820) = 3103
//    // To combine them we rescale RMS into probit scale since it's easier: it's just
//    // (RMS>>1 + RMS>>2) so previously we get 
//    // rescale RMS = 3072
//    // rescale probit = 3103
//    // RMS error is bounded to probit as well, and then probit error is deadbanded.
//    // Bounds mean max RMS positive offset is (9158-4820) = 4338*1.5 = 6507
//    // Probit deadband is designed to allow for scale variations of 1->1.4
//    // Scale of 1.4 is probit error of ~1230
//    // so if probit error < 1230 or > -300 probit error = 0
//    // 
//    // FIRST PASS JUST USE SCALE ERROR
//    //
//    wire rms_scale_done;
//    wire [19:0] rms_scale;
    
    
//    // agc_tick indicates the beginning of the AGC period
//    // Note that the AGC period is *longer* than the measurement
//    // period, which is fine.
//    // Our measurement period operates over 2^20 samples or
//    // 2^17 (131,072) clocks.
//    wire agc_ce;
//    wire agc_done;
//    // agc_done indicates LAST cycle, so begin calc right after.
//    reg begin_calc = 0;
//    always @(posedge clk_i) begin_calc <= agc_done;
//    // this comes from the register core. to resynchronize,
//    // you disable agc, wait, and then enable it later.
//    wire agc_enable;
//    reg local_agc_tick = 0;
//    always @(posedge clk_i) local_agc_tick <= agc_enable && agc_tick_i;

//    // also comes from register core.
//    wire agc_lfsr_reset;
//    reg agc_synced = 0;
//    reg agc_local_sync = 0;
//    always @(posedge clk_i) begin
//        if (agc_lfsr_reset) agc_synced <= 1'b0;
//        else if (global_sync_i) agc_synced <= 1'b1;
        
//        agc_local_sync <= global_sync_i && !agc_synced;                   
//    end   

//    agc_timer u_timer(.clk_i(clk_i),
//                      .agc_tick_i(local_agc_tick),
//                      .agc_ce_o(agc_ce),
//                      .agc_done_o(agc_done));
    
//    lfsr_rms_mux u_mux(.clk_i(clk_i),
//                       .sync_i(agc_local_sync),
//                       .rst_i(agc_lfsr_reset),
//                       .in_i(abs_vals),
//                       .out_o(abs_val));
    
//    square_5bit_accumulator #(.NBITS(24),
//                              .RESET_VALUE(SQ_OFFSET))
//                            u_rms_acc(.clk_i(clk_i),
//                                      .in_i(abs_val),
//                                      .ce_i(agc_ce),
//                                      .rst_i(agc_local_tick),
//                                      .accum_o(square_accum));
//    // first step is sqrt
//    nr_sqrt #(.NBITS(24)) u_rms_sqrt(.clk_i(clk_i),
//                                     .calc_i(begin_calc),
//                                     .in_i(square_accum),
//                                     .out_o(rms),
//                                     .valid_o(rms_done));
//    // next step is reciprocal
//    slow_reciprocal #(.NBITS(22)) u_rms_recip(.clk_i(clk_i),
//                                              .calc_i(rms_done),
//                                              .in_i(rms),
//                                              .out_o(rms_scale),
//                                              .valid_o(rms_done));


endmodule
