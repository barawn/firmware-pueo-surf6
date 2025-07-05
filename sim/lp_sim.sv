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
    tb_rclk #(.PERIOD(2)) u_clk(.clk(clk));
    
    reg [127:0] adc_indata = {128{1'b0}};
    wire [7:0][15:0] outdata;

    halfband uut(.aclk(clk),
                 .s_axis_data_tdata(adc_indata),
                 .s_axis_data_tvalid(1'b1),
                 .m_axis_data_tdata(outdata));

    initial begin
        #100;
        @(posedge clk);
        #0.1 adc_indata[15:0] <= 16'd1000;
        @(posedge clk);
        #0.1 adc_indata[15:0] <= 16'd0;
    end

endmodule
