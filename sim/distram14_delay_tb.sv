`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/13/2025 12:17:42 PM
// Design Name: 
// Module Name: distram14_delay_tb
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


module distram14_delay_tb(

    );
    wire clk;
    tb_rclk #(.PERIOD(5)) u_clk(.clk(clk));
    
    reg [13:0] din = {14{1'b0}};
    wire [13:0] dout;
    
    // 4 = 5 clocks worth of delay.
    distram14_delay #(.DELAY(4))
        u_delay(.clk_i(clk),
                .rst_i(1'b0),
                .dat_i(din),
                .dat_o(dout));
    initial begin
        #100;
        @(posedge clk);
        #0.1 din = 14'h1234;
        @(posedge clk);
        #0.1 din = 14'h0000;
    end                

endmodule
