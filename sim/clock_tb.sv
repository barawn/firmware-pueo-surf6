`timescale 1ns / 1ps

module clock_tb;

    wire aclk;
    tb_rclk #(.PERIOD(2.666)) u_clk(.clk(aclk));
    
    wire ifclk;
    wire ifclk_x2;
    wire ifclk_locked;
    wire memclk;
    wire memclk_locked;
    
    reg aclk_reset = 0;
    defparam u_ifclk.inst.plle4_adv_inst.CLKIN_PERIOD = 2.667;
    ifclk_pll u_ifclk(.clk_in1(aclk),.reset(aclk_reset),
                      .clk_out1(ifclk),.clk_out2(ifclk_x2),
                      .locked(ifclk_locked));
    memclk_pll u_memclk(.clk_in1(aclk),.reset(aclk_reset),
                        .clk_out1(memclk),
                        .locked(memclk_locked));
    
    wire memclk_sync;
    wire aclk_sync;
    wire sync_toggle;
    
    pueo_clk_phase_v2 u_clkphase(.aclk(aclk),.memclk(memclk),.syncclk(ifclk),
                                 .locked_i(ifclk_locked && memclk_locked),
                                 .memclk_sync_o(memclk_sync),
                                 .aclk_sync_o(aclk_sync),
                                 .syncclk_toggle_o(sync_toggle));

    initial begin
        #100;
        @(posedge aclk);
        #0.1 aclk_reset = 1;
        #100;
        @(posedge aclk);
        #0.1 aclk_reset = 0;

        #1000;
        @(posedge aclk);
        #0.1 aclk_reset = 1;
        #100;
        @(posedge aclk);
        #0.1 aclk_reset = 0;
        
    end

endmodule
