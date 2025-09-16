`timescale 1ns / 1ps
`include "interfaces.vh"

module L1_trigger_v2_tb;

    wire wb_clk;
    wire wb_rst = 0;
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
    
    wire [45:0] trigger;
    wire trigger_count_done;
    
    reg [7:0][7:0][4:0] dat_in = {8*8{5'd16}};
    
    `DEFINE_WB_IF( wb_ , 13, 32 );
    reg cyc = 0;
    reg we = 0;
    reg [12:0] adr = {13{1'b0}};
    reg [31:0] dat = {32{1'b0}};
    
    assign wb_cyc_o = cyc;
    assign wb_stb_o = cyc;
    assign wb_we_o = we;
    assign wb_sel_o = {4{we}};
    assign wb_dat_o = dat;
    assign wb_adr_o = adr;
    
    L1_trigger_v2 #(.NBEAMS(48),.USE_V3("TRUE")) 
        uut(.wb_clk_i(wb_clk),
            .wb_rst_i(wb_rst),
            `CONNECT_WBS_IFM( wb_ , wb_ ),
            
            .tclk(aclk),
            .dat_i(dat_in),
            
            .aclk(aclk),
            .aclk_phase_i(this_clk_phase),
            
            .ifclk(ifclk),
            .trigger_o(trigger),
            .trigger_count_done_o(trigger_count_done));

    task wb_write;
        input [15:0] addr;
        input [31:0] data;
        begin
            @(posedge wb_clk);
            #0.1 cyc = 1;
                 we = 1;
                 adr = addr;
                 dat = data;
            while (!wb_ack_i) @(posedge wb_clk);
            #0.1 cyc = 0;
                 we = 0;
                 adr = {12{1'b0}};
                 dat = {32{1'b0}};
            @(posedge wb_clk);                
        end
    endtask
    
    reg [31:0] wb_rd_data = {32{1'b0}};
    always @(posedge wb_clk) begin
        if (wb_cyc_o && wb_stb_o && wb_ack_i)
            wb_rd_data <= wb_dat_i;
    end
    
    task wb_read;
        input [15:0] addr;
        begin
            @(posedge wb_clk);
            #0.1 cyc = 1;
                 adr = addr;
            while (!wb_ack_i) @(posedge wb_clk);
            #0.1 cyc = 0;
                 adr = {12{1'b0}};
                 $display("time %0t read 0x%0h", $time, wb_rd_data);
            @(posedge wb_clk);                                  
        end
    endtask
                
    initial begin
        #250;
        
        wb_write(16'h0800, 32'd5000);
        wb_write(16'h0804, 32'd4000);
        wb_write(16'h0A00, 32'd5001);
        wb_write(16'h0A04, 32'd300);

        wb_write(16'h1800, 32'h2);
        wb_write(16'h1808, 32'h200);
        #1000;
        wb_read(16'h1808);        
        
        #500;
        
        @(posedge aclk);
        // our inputs are offset binary so add 16 to everything
        #0.01 dat_in[0][0] <= -1 + 16;
              dat_in[1][0] <= 0 + 16;    
              dat_in[2][0] <= -2 + 16;
              dat_in[3][0] <= -3 + 16;
              dat_in[4][0] <= 15 + 16;
              dat_in[5][0] <= -7 + 16;
              dat_in[6][0] <= -8 + 16;
              dat_in[7][0] <= 10 + 16;
              // sum should be 8, square should be 64
        @(posedge aclk);
        #0.01 dat_in[0][0] <= 0 + 16;
              dat_in[1][0] <= 0 + 16;    
              dat_in[2][0] <= 0 + 16;
              dat_in[3][0] <= 0 + 16;
              dat_in[4][0] <= 0 + 16;
              dat_in[5][0] <= 0 + 16;
              dat_in[6][0] <= 0 + 16;
              dat_in[7][0] <= 0 + 16;
                      
    end    
    
endmodule
