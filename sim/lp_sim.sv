`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/04/2025 10:21:29 PM
// Design Name: 
// Module Name: lp_sim
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


module lp_sim;

    wire clk;
    tb_rclk #(.PERIOD(2.667)) u_clk(.clk(clk));

    reg [1:0] clk_phase = {2{1'b0}};
    wire this_clk_phase = clk_phase == 2'b00;
    always @(posedge clk) begin
        if (clk_phase == 2'b10) clk_phase <= #0.01 2'b00;
        else clk_phase <= #0.01 clk_phase + 1;
    end
    
    reg [7:0][11:0] adc_indata = {96{1'b0}};
    wire [47:0] tmp_out;

    reg rst = 0;
    wire [7:0][12:0] filt0_out;

    wire [3:0][12:0] filt1_out;

    wire [7:0][15:0] systA_out;
    wire [7:0][15:0] systA1_out;
    // ok need to think here:
    // systA in the matched filter corresponds to samples 0/3 (subtype 0)
    // and samples 2/4 (subtype 1) when generating sample 7.
    // Index rotation means:
    //              subtype 0       subtype 1
    // sample 7     0       3       2       4
    // sample 6     7z^-1   2       1       3
    // sample 5     6z^-1   1       0       2
    // sample 4     5z^-1   0       7z^-1   1
    // sample 3     4z^-1   7z^-1   6z^-1   0
    // sample 2     3z^-1   6z^-1   5z^-1   7z^-1
    // sample 1     2z^-1   5z^-1   4z^-1   6z^-1
    // sample 0     1z^-1   4z^-1   3z^-1   5z^-1
    // a half-and-half could nominally help if we instead did 0/3 and 2/5?
    // that's not half bad but we'll think about that later
    reg [11:0] s6_storeA1 = {12{1'b0}};
    always @(posedge clk) s6_storeA1 <= adc_indata[7];
    systA_matched_filter_v2 #(.SUBTYPE(0),
                              .INBITS(12))
                               uutB(.clk_i(clk),
                                    .inA0_i( adc_indata[0]  ),
                                    .inA1_i( s6_storeA1     ),
                                    .inB0_i( adc_indata[3]  ),
                                    .inB1_i( adc_indata[2]  ),
                                    .out0_o( systA_out[7]   ),
                                    .out1_o( systA_out[6]   ));
    systA_matched_filter_v2 #(.SUBTYPE(1),
                              .INBITS(12))
                              uutC(.clk_i(clk),
                                   .inA0_i( adc_indata[2]   ),
                                   .inA1_i( adc_indata[1]   ),
                                   .inB0_i( adc_indata[4]   ),
                                   .inB1_i( adc_indata[3]   ),
                                   .out0_o( systA1_out[7]   ),
                                   .out1_o( systA1_out[6]   ));
    shannon_whitaker_lpfull_v3 #(.INBITS(12))
                               uut(.clk_i(clk),
                                   .rst_i(rst),
                                   .dat_i(adc_indata),
                                   .dat_o(filt0_out));

    twothirds_lpfull #(.INBITS(12))
        twothirds(.clk_i(clk),
                  .clk_phase_i(this_clk_phase),
                  .rst_i(rst),
                  .dat_i({ adc_indata[6],
                           adc_indata[4],
                           adc_indata[2],
                           adc_indata[0] }),
                  .dat_o(filt1_out));

    initial begin
        #100;
        @(posedge clk);
        #0.1 adc_indata[6] = 16'd1000;
//             adc_indata[4] = 16'd1000;
        @(posedge clk);
        #0.1 adc_indata[6] = 16'd0;
//             adc_indata[4] = 16'd0;
        #100;
        @(posedge clk);
        #0.1 adc_indata[0] = 16'd1000;
//             adc_indata[2] = 16'd1000;
        @(posedge clk);
        #0.1 adc_indata[0] = 16'd0;
//             adc_indata[2] = 16'd0;
        #100;
        @(posedge clk);
        #0.1 adc_indata[1] = 16'd1000;
        @(posedge clk);
        #0.1 adc_indata[1] = 16'd0;
        
        #100;
        @(posedge clk);
        #0.1 adc_indata[2] = 16'd1000;
        @(posedge clk);
        #0.1 adc_indata[2] = 16'd0;
        
        #100;
        @(posedge clk);
        #0.1 adc_indata[3] = 16'd1000;
        @(posedge clk);
        #0.1 adc_indata[3] = 16'd0;

        #100;
        @(posedge clk);
        #0.1 adc_indata[4] = 16'd1000;
        @(posedge clk);
        #0.1 adc_indata[4] = 16'd0;
        
        #100;
        @(posedge clk);
        #0.1 adc_indata[5] = 16'd1000;
        @(posedge clk);
        #0.1 adc_indata[5] = 16'd0;
        
        #100;
        @(posedge clk);
        #0.1 adc_indata[7] = 16'd1000;
        @(posedge clk);
        #0.1 adc_indata[7] = 16'd0;

        #100;
        // timing check the systA filter:
        // if we excite both 0 and 2 at the same time 6 and 7 should
        // show the matched filter
        @(posedge clk);
        #0.1 adc_indata[0] = 16'd1000;
             adc_indata[2] = 16'd1000;
        @(posedge clk);
        #0.1 adc_indata[0] = 16'd0;
             adc_indata[2] = 16'd0;
        // timing check the subtype 1 filter
        // excite both 2 and 3 at the same time
        #100;
        @(posedge clk);
        #0.1 adc_indata[2] = 16'd1000;
             adc_indata[3] = 16'd1000;
        @(posedge clk);
        #0.1 adc_indata[2] = 16'd0;
             adc_indata[3] = 16'd0;             
    end

endmodule
