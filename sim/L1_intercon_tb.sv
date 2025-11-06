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
    wire aclk;
    tb_rclk #(.PERIOD(2.667)) u_aclk(.clk(aclk));

    reg aclk_reset = 1;
    wire ifclk;
    wire ifclk_x2;
    wire ifclk_locked;
    defparam u_ifclk.inst.plle4_adv_inst.CLKIN_PERIOD = 2.667;
    ifclk_pll u_ifclk(.clk_in1(aclk),.reset(aclk_reset),
                      .clk_out1(ifclk),.clk_out2(ifclk_x2),
                      .locked(ifclk_locked));
    
    reg [1:0] clk_phase = {2{1'b0}};
    wire this_clk_phase;
    assign this_clk_phase = (clk_phase == 2'd2);
    always @(posedge aclk) begin
        if (clk_phase == 2'd2) clk_phase <= #0.01 {2{1'b0}};
        else clk_phase <= #0.01 clk_phase + 1;
    end    

    reg runrst = 0;
    reg runstop = 0;
    wire [31:0] trig_tdata;
    wire        trig_tvalid;
    wire        trig_tready = 1'b1;
    L1_trigger_wrapper_v2 uut(.wb_clk_i(wb_clk),                            
                              `CONNECT_WBS_IFM( wb_ , wb_ ),
                              .aclk(aclk),
                              .aclk_phase_i(this_clk_phase),
                              .tclk(aclk),
                              .dat_i( {8*96{1'b0}} ),
                              .ifclk(ifclk),
                              .ifclk_running_i(ifclk_locked),
                              .runrst_i(runrst),
                              .runstop_i(runstop),
                              `CONNECT_AXI4S_MIN_IF(m_trig_, trig_ )
                              );

    task wb_write;
        input [14:0] address;
        input [31:0] data;
        begin
            @(posedge wb_clk); #1 cyc = 1;
                                  we = 1;
                                  adr = address;
                                  dat = data;
            while (!wb_ack_i) @(posedge wb_clk);
            #1 cyc = 0; we = 0;
            @(posedge wb_clk);                                  
        end
    endtask        

    initial begin
        #100;
        @(posedge aclk); #1 aclk_reset = 0;

        #1000;

        wb_write(15'h2008, 32'h00000000);
        wb_write(15'h200C, 32'h80000000);
        
        #100;
        wb_write(15'h2008, 32'hFFFFFFFF);        
    end

endmodule
