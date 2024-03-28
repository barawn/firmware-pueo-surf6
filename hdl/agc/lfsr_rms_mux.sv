`timescale 1ns / 1ps
// mux 8 samples into one for RMS-ing using LFSR
// 32 total inputs
// The LFSR here is tiny because we just basically want to get out of CW land.
// It's length 127 and we generate 3 bits per so it repeats like every 42 clocks.
//  - if you can't guess, the reason why we did 127 is because it actually takes
//    fully 127 clocks (1016 samples) to fully repeat the channel select.
//
// this also only works on 4 bits because we've already abs-ed everything
module lfsr_rms_mux(
        input clk_i,
        input [31:0] in_i,
        input sync_i,
        input rst_i,
        output [3:0] out_o
    );

    wire [3:0] in_vec[7:0];
    generate
        genvar i;
        for (i=0;i<8;i=i+1) begin
            assign in_vec[i] = in_i[4*i +: 4];
        end
    endgenerate    
    wire [2:0] sample_select;
    
    xil_tiny_lfsr_3bit uut(.clk_i(clk_i),
                           .rst_i(rst_i),
                           .start_i(sync_i),
                           .out_o(sample_select));

    reg [3:0] out_mux = {4{1'b0}};
    always @(posedge clk_i) begin
        out_mux <= in_vec[sample_select];
    end
    
    assign out_o = out_mux;
        
endmodule
