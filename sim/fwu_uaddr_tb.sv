`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/25/2024 11:28:17 AM
// Design Name: 
// Module Name: fwu_uaddr_tb
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


module fwu_uaddr_tb;

    wire clk;
    tb_rclk #(.PERIOD(10.0)) u_clk(.clk(clk));
    
    reg [7:0] ce_ctr = 8'h00;
    always @(posedge clk) begin
        ce_ctr <= #1 ce_ctr + 1;
    end
    wire ce = ((ce_ctr % 8) == 0);
    
    reg rst = 0;
    
    wire [7:0] uaddr;
    fwupd_uaddr uut(.clk_i(clk),
                    .ce_i(ce),
                    .rstb_i(~rst),
                    .uaddr_o(uaddr));

    initial begin
        #100;
        @(posedge clk); #1 rst = 1;
        @(posedge clk); #1 rst = 0;
    end    

endmodule
