`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/05/2025 06:47:49 PM
// Design Name: 
// Module Name: L1_intercon_tb
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

`include "interfaces.vh"
module L1_intercon_tb;

    `DEFINE_WB_IF( wb_ , 15, 32 );
    `DEFINE_WB_IF( thresh_ , 13, 32 );
    `DEFINE_WB_IF( generator_ , 13, 32 );
    `DEFINE_WB_IF( agc_ , 13, 32 );
    `DEFINE_WB_IF( bq_ , 13, 32);

    reg cyc = 0;
    reg [14:0] adr = 0;
    reg we = 0;
    reg [31:0] dat = {32{1'b0}};
    reg ack = 0;
    
    assign wb_cyc_o = cyc;
    assign wb_stb_o = cyc;
    assign wb_adr_o = adr;
    assign wb_dat_o = dat;
    assign wb_we_o = we;
    assign wb_sel_o = 4'hF;
    
    wire wb_clk;
    tb_rclk #(.PERIOD(10.0)) u_clk(.clk(wb_clk));

    always @(posedge wb_clk) begin
        ack <= (thresh_cyc_o || generator_cyc_o || agc_cyc_o || bq_cyc_o);
    end
    
    assign thresh_ack_i = ack && thresh_cyc_o;
    assign generator_ack_i = ack && generator_cyc_o;
    assign agc_ack_i = ack && agc_cyc_o;
    assign bq_ack_i = ack && bq_cyc_o;    
    
    assign thresh_dat_i = 32'hBABEFACE;
    assign generator_dat_i = 32'hDEADBEEF;
    assign agc_dat_i = 32'h8BADF00D;
    assign bq_dat_i = 32'hCAFEBABE;
    
    assign thresh_err_i = 1'b0;
    assign generator_err_i = 1'b0;
    assign agc_err_i = 1'b0;
    assign bq_err_i = 1'b0;

    assign thresh_rty_i = 1'b0;
    assign generator_rty_i = 1'b0;
    assign agc_rty_i = 1'b0;
    assign bq_rty_i = 1'b0;
    
    reg clock_en = 0;
    
    L1_trigger_intercon uut(.wb_clk_i(wb_clk),
                            .clock_enabled_i(clock_en),
                            `CONNECT_WBS_IFM( wb_ , wb_ ),
                            `CONNECT_WBM_IFM( thresh_ , thresh_ ),
                            `CONNECT_WBM_IFM( generator_ , generator_ ),
                            `CONNECT_WBM_IFM( agc_ , agc_ ),
                            `CONNECT_WBM_IFM( bq_ , bq_ ));

    initial begin
        #100;
        @(posedge wb_clk); #1 cyc = 1;
        while (!wb_ack_i) @(posedge wb_clk);
        #1 cyc = 0;
        
        #100;
        @(posedge wb_clk); #1 clock_en = 1;
        
        #100;
        @(posedge wb_clk); #1 cyc = 1;
        while (!wb_ack_i) @(posedge wb_clk);
        #1 cyc = 0;

        #100;
        @(posedge wb_clk); #1 cyc = 1;
                              we = 1;
                              dat = 32'hC0FED0CC;
        while (!wb_ack_i) @(posedge wb_clk);
        #1 cyc = 0; we = 0;
        
        #100;
        adr = 15'h2000;
        @(posedge wb_clk); #1 cyc = 1;
        while (!wb_ack_i) @(posedge wb_clk);
        #1 cyc = 0;

        #100;
        adr = 15'h2000;
        @(posedge wb_clk); #1 cyc = 1;
                              we = 1;
                              dat = 32'h00C0FFEE;
        while (!wb_ack_i) @(posedge wb_clk);
        #1 cyc = 0; we = 0;
        
        #100;
        adr = 15'h4000;
        @(posedge wb_clk); #1 cyc = 1;
        while (!wb_ack_i) @(posedge wb_clk);
        #1 cyc = 0;

        #100;
        adr = 15'h4000;
        @(posedge wb_clk); #1 cyc = 1;
                              we = 1;
                              dat = 32'hCAB00D1E;
        while (!wb_ack_i) @(posedge wb_clk);
        #1 cyc = 0; we = 0;


        #100;
        adr = 15'h6000;
        @(posedge wb_clk); #1 cyc = 1;
        while (!wb_ack_i) @(posedge wb_clk);
        #1 cyc = 0;

        #100;
        adr = 15'h6000;
        @(posedge wb_clk); #1 cyc = 1;
                              we = 1;
                              dat = 32'hBEEFBABE;
        while (!wb_ack_i) @(posedge wb_clk);
        #1 cyc = 0; we = 0;

    end

endmodule
