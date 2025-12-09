`timescale 1ns / 1ps
`include "interfaces.vh"
`include "L1Beams_header.vh"
module beamformV3_trigger_tb;

    parameter   THIS_BENCH = "PULSE";
    parameter   ALIGNED_BEAM = 0;

    // Gaussian Random Parameters
    int seed = 1;
    // int stim_mean = 15;
    int stim_sdev = 4;//4; // Note that max value is 32
    int stim_val = 0;
    int cycling_num = 0;
    int cycling_offset = 0;
    int pulse_height = 8;//0;

    localparam  NBITS=5;
    localparam  NSAMP=8; 
    localparam  NCHAN=8;

    // Clocks
    wire clk;
    tb_rclk #(.PERIOD(5.0)) u_clk(.clk(clk));

    localparam NBEAMS = 8;

    // NOTE THE BIG-ENDIAN ARRAYS HERE
    localparam int delay_array [0:(`BEAM_TOTAL)-1][0:NCHAN-1] = `BEAM_ANTENNA_DELAYS;
    localparam int v3Delay [0:NCHAN-1] = {0,10,10,10,2,13,13,13};

    reg [7:0][39:0]     in_data_reg         = {{40{1'b0}}, {40{1'b0}}, {40{1'b0}}, {40{1'b0}}, {40{1'b0}}, {40{1'b0}}, {40{1'b0}}, {40{1'b0}}};
    reg [17:0]          thresh_reg          = 18'd0;
    reg [NBEAMS-1:0]    thresh_ce_reg       = {NBEAMS{1'b0}};
    reg                 update_reg          = 1'b0;
    reg [NBEAMS-1:0]    trigger_reg; 

    wire [7:0][39:0]         in_data        = in_data_reg;
    wire [17:0]         thresh              = thresh_reg;
    wire [NBEAMS-1:0]   thresh_ce           = thresh_ce_reg;
    wire        update                      = update_reg;
    wire [NBEAMS-1:0]   trigger;

    assign trigger_reg = trigger;

    // Do some vectorizing for debugging
    wire [7:0][7:0][4:0] vectorized_data;
    

    assign vectorized_data = in_data_reg;

    beamform_trigger_v3
     u_beam_trigger(
        .clk_i(clk),
        .data_i(in_data),

        .thresh_i(thresh),
        .thresh_wr_i(thresh_ce),
        .thresh_update_i(update),
        .trigger_o(trigger)
    );


// module beamform_trigger_v3 #(parameter FULL = "TRUE",
//                              parameter DEBUG = "FALSE",
//                              parameter SKEWED_TOP = "FALSE",
//                              parameter USE_ALL_BEAMS = "TRUE",
//                              localparam NBEAMS = (FULL == "TRUE") ? NUM_BEAM : NUM_DUMMY,
//                              localparam NBITS=5,
//                              localparam NSAMP=8,
//                              localparam NCHAN=8)(
//         input clk_i,
//         input [NCHAN-1:0][NSAMP*NBITS-1:0] data_i,
//         input [18*2-1:0] thresh_i,
//         input [1:0] thresh_wr_i,
//         input [1:0] thresh_update_i,
//         output [2*NBEAMS-1:0] trigger_o
//     );

    initial begin : VALLOOP
        $display("Setup");
        for(int j=0; j<25; j=j+1) begin
            #1.75;
            @(posedge clk);
        end
        #1.75;
        @(posedge clk);
        #1.75;
        $display("Initial Threshold Load");
        for(int beam_idx=0; beam_idx<NBEAMS; beam_idx = beam_idx+2) begin
            update_reg = 1'b0;
            thresh_reg = 18'd9000; 
            thresh_ce_reg[beam_idx +: 2] = 2'b10; // Load this threshold into A.
            @(posedge clk);
            thresh_reg = 18'd9000; 
            thresh_ce_reg[beam_idx +: 2] = 2'b01; // Load this threshold into B.
            #1.75;
            @(posedge clk);
            update_reg = 1'b1; // Apply new thresholds
            #1.75;
            @(posedge clk);
            #1.75;
            thresh_ce_reg[beam_idx +: 2] = 2'b00;
            update_reg = 1'b0;
            @(posedge clk);
            #1.75;
        end
        for(int i=0; i<64; i=i+1) begin  
            @(posedge clk);
            #1.75;
        end
        $display("Initial Threshold Has Been Loaded");

        if (THIS_BENCH == "ALIGNMENT") begin : ALIGNMENT_RUN    
            $display("Running Alignment");
            forever begin
                @(posedge clk);
                #1.75;
                for(int j=0; j<8; j=j+1) begin : CHANNEL_FILL
                    in_data_reg[j] = {{5'd0},{5'd0},{5'd0},{5'd0},{5'd0},{5'd0},{5'd0},{5'd0}};
                end
                for(int j=0; j<5; j=j+1) begin : CHANNEL_FILL
                    @(posedge clk);
                end
                for(int i=0; i<4; i=i+1) begin  
                    @(posedge clk);
                    #1.75;
                    for(int j=0; j<8; j=j+1) begin : CHANNEL_FILL
                        in_data_reg[j] = {{5'd7},{5'd6},{5'd5},{5'd4},{5'd3},{5'd2},{5'd1},{5'd0}};
                        in_data_reg[j] = in_data_reg[j] + i*{{5'd8},{5'd8},{5'd8},{5'd8},{5'd8},{5'd8},{5'd8},{5'd8}};
                    end
                end 
            end
        end else if (THIS_BENCH == "CHANNELS") begin : CHANNELS_RUN    
            $display("Running Channels");
            forever begin
                @(posedge clk);
                #1.75;
                for(int j=0; j<8; j=j+1) begin : CHANNEL_FILL
                    in_data_reg[j] = {{5'd0},{5'd0},{5'd0},{5'd0},{5'd0},{5'd0},{5'd0},{5'd0}};
                end
                for(int j=0; j<5; j=j+1) begin : CHANNEL_FILL
                    @(posedge clk);
                end
                for(int i=0; i<4; i=i+1) begin  
                    @(posedge clk);
                    #1.75;
                    for(int j=0; j<8; j=j+1) begin : CHANNEL_FILL
                        // in_data_reg[j] = {{5'd7},{5'd6},{5'd5},{5'd4},{5'd3},{5'd2},{5'd1},{5'd0}};
                        in_data_reg[j] = j*{{5'd1},{5'd1},{5'd1},{5'd1},{5'd1},{5'd1},{5'd1},{5'd1}};
                    end
                end 
            end
        end else if (THIS_BENCH == "PULSE") begin : PULSE_RUN    
            $display("Running Single Pulse");
            forever begin
                for(int i=0; i<64; i++) begin: FILL_DELAYED_PULSES
                    #0.01;
                    @(posedge clk);
                    for(int j=0; j<NCHAN; j=j+1) begin : CHANNEL_FILL_DELAYED_PULSES
                        for(int k=0; k<NSAMP; k=k+1) begin : SAMPLE_FILL_DELAYED_PULSES
                            cycling_num = i*8+k + v3Delay[j];
                            cycling_offset = 8*50;
                                if(k % 2 == 0) begin
                                    stim_val = 15;
                                end else begin
                                    stim_val = 16;
                                end
                            if((cycling_num-cycling_offset) == 0) begin : ADD_PULSE
                                stim_val = stim_val + 4;
                            end else begin
                                stim_val = stim_val + 0;
                            end
                            in_data_reg[j][k*5 +: 5] = stim_val;
                        end
                    end
                end
            end
        end else begin : GAUSS_AND_PULSE_RUN
            forever begin
                for(int i=0; i<64; i++) begin: FILL_DELAYED_PULSES
                    #0.01;
                    @(posedge clk);
                    for(int j=0; j<NCHAN; j=j+1) begin : CHANNEL_FILL_DELAYED_PULSES
                        for(int k=0; k<NSAMP; k=k+1) begin : SAMPLE_FILL_DELAYED_PULSES
                            do begin
                                if($random() > 0) begin
                                    stim_val = $dist_normal(seed, 15, stim_sdev);
                                end else begin
                                    stim_val = $dist_normal(seed, 16, stim_sdev);
                                end
                            end while(stim_val > 31 || stim_val < 0); // Don't leave 5 bit range please
                            cycling_num = i*8+k + v3Delay[j];
                            cycling_offset = 8*50;
                            if((cycling_num-cycling_offset) < 12 && (cycling_num-cycling_offset) > 0) begin : ADD_PULSE
                                // if(j==0) begin
                                //     $display($sformatf("Number: %1d, rotating: %1d", (cycling_num-cycling_offset), (cycling_num-cycling_offset)%4));
                                // end
                                if((cycling_num-cycling_offset)%4 > 1) begin
                                    stim_val = stim_val + pulse_height/((cycling_num-cycling_offset)/3 + 1);
                                end else begin
                                    stim_val = stim_val - pulse_height/((cycling_num-cycling_offset)/3 + 1);
                                end
                                if(stim_val > 31) begin
                                    stim_val = 31;
                                end else if (stim_val < 0)begin
                                    stim_val = 0; // ~ 2.5 SNR
                                end
                            end
                            in_data_reg[j][k*5 +: 5] = stim_val;
                        end
                    end
                end
            end
        end
    end



    
endmodule
