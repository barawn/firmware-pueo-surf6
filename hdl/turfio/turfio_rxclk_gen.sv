`timescale 1ns / 1ps
// Clocking portion of the TURFIO receive interface.
// The TURFIO receive interface captures using RXCLK
// so that we have an idea of the latency path through the whole
// thing.
module turfio_rxclk_gen #(parameter INV_RXCLK = 1'b0)(
        input rxclk_in,
        output rxclk_o,
        output rxclk_x2_o,
        input rst_i,
        output locked_o,
        input ps_clk_i,
        input ps_en_i,
        output ps_done_o
    );

    // Easier than TURFIO since there are optional inverters on CLKIN
    // for ultrascale+ and not 7 series
    
    // RXCLK feedback output to bufg
    wire rxclk_fb_to_bufg;
    // RXCLK feedback bufg
    wire rxclk_fb_bufg;
    // RXCLK main output 
    wire rxclk_to_bufg;
    // RXCLKx2 main output
    wire rxclk_x2_to_bufg;
    
    // Clocking    
    BUFG u_rxclk_fb(.I(rxclk_fb_to_bufg),.O(rxclk_fb_bufg));
    BUFG u_rxclk_bufg(.I(rxclk_to_bufg),.O(rxclk_o));
    BUFG u_rxclk_x2_bufg(.I(rxclk_x2_to_bufg),.O(rxclk_x2_o));
    MMCME4_ADV #( .CLKFBOUT_MULT_F(8.000),
                  .CLKFBOUT_PHASE(0.000),
                  .CLKIN1_PERIOD(8.000),
                  .CLKOUT1_DIVIDE(4),
                  .IS_CLKIN1_INVERTED(INV_RXCLK),
                  .CLKOUT1_USE_FINE_PS("TRUE"),
                  .CLKOUT0_DIVIDE_F(8.000),
                  .CLKOUT0_USE_FINE_PS("TRUE"))
        u_rxclk_mmcm(.CLKIN1(rxclk_in),
                     .CLKFBIN(rxclk_fb_bufg),
                     .PWRDWN(1'b0),
                     .CLKFBOUT(rxclk_fb_to_bufg),
                     .CLKOUT0(rxclk_to_bufg),
                     .CLKOUT1(rxclk_x2_to_bufg),
                     .RST(rst_i),
                     .LOCKED(locked_o),
                     .PSCLK(ps_clk_i),
                     .PSEN(ps_en_i),
                     .PSINCDEC(1'b1),
                     .PSDONE(ps_done_o));    
    
endmodule
