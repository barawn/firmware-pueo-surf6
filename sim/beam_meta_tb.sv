`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/30/2025 02:25:05 PM
// Design Name: 
// Module Name: beam_meta_tb
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


module beam_meta_tb;

    wire clk;
    tb_rclk #(.PERIOD(5)) u_clk(.clk(clk));
    
    reg [47:0] beams = {48{1'b0}};
    reg trig = 0;
    
    wire [7:0] meta;
    wire trig_out;
    
    beam_meta_builder uut(.clk_i(clk),
                          .trig_i(trig),
                          .beam_i(beams),
                          .meta_o(meta),
                          .trig_o(trig_out));
                          
    initial begin
        #100;
        @(posedge clk);
        // ok beam 0 trips bit 7. Let's try it alone,
        // then try PEGGING that bit and see what happens.
        // The other beams on bit 7 are
        // 0, 1, 2, 7, 8, 9, 14, 15, 16, 35, 36, 37
        #0.1 trig = 1;
             beams[7] = 1;             
        @(posedge clk);
        #0.1 trig = 0;
             beams[7] = 0;
        #100;
        @(posedge clk);
        #0.1 trig = 1;
             beams[12] = 1;
        @(posedge clk);
        #0.1 trig = 0;
             beams[12] = 0;             
    end                          

endmodule
