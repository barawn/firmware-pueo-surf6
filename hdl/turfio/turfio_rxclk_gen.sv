`timescale 1ns / 1ps
// Clocking portion of the TURFIO receive interface.
// This is way more complicated than the TURFIO -> TURF case.
module turfio_rxclk_gen #(parameter INV_RXCLK = 1'b0)(
        input rxclk_in,
        // RACKCLK is the *raw* RXCLK input. It comes straight from
        // the TURFIO, and doesn't go through the MMCM.
        // It's used for the RACKctl interface along with the
        // rxclk ok detection.
        output rackclk_o,
        // These are outputs from the MMCM.
        output rxclk_o,
        output rxclk_x2_o,
        output rxclk_x3_o,
        
        output clk300_o,
        // synchronous to rxclk_x3_o, indicates first clock of
        // the 3-phase rxclk cycle.
        output rxclk_ce_o,
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
    // RXCLKx3 main output
    wire rxclk_x3_to_bufg;
    // CLK300 main output
    wire clk300_to_bufg;
    
    // Clocking.
    BUFG u_rackclk(.I(rxclk_in),.O(rackclk_o));    
    BUFG u_rxclk_fb(.I(rxclk_fb_to_bufg),.O(rxclk_fb_bufg));
    BUFG u_rxclk_bufg(.I(rxclk_to_bufg),.O(rxclk_o));
    BUFG u_rxclk_x2_bufg(.I(rxclk_x2_to_bufg),.O(rxclk_x2_o));
    BUFG u_rxclk_x3_bufg(.I(rxclk_x3_to_bufg),.O(rxclk_x3_o));
    BUFG u_clk300_bufg(.I(clk300_to_bufg),.O(clk300_o));
    // The VCO range is 800 - 1600 MHz.
    // We need something that is a multiple of
    // 125, 250, 300, and 375.
    // That's 1500 MHz.
    localparam VCO_MULTIPLIER = 12.000;
    localparam RXCLK_DIVIDE =  12;
    localparam RXCLKx2_DIVIDE = 6;
    localparam RXCLKx3_DIVIDE = 4;
    localparam CLK300_DIVIDE = 5;

    // Xilinx bitches at me if CLKOUT1 drives the IO cells (rxclk_x2) for some reason.
    // So clkout0 is rxclk_x2 and clkout1 is rxclk
    MMCME4_ADV #( .CLKFBOUT_MULT_F(VCO_MULTIPLIER),
                  .CLKFBOUT_PHASE(0.000),
                  .CLKIN1_PERIOD(8.000),
                  .IS_CLKIN1_INVERTED(INV_RXCLK),
                  .CLKOUT3_DIVIDE(CLK300_DIVIDE),
                  .CLKOUT3_USE_FINE_PS("FALSE"),
                  .CLKOUT2_DIVIDE(RXCLKx3_DIVIDE),
                  .CLKOUT2_USE_FINE_PS("TRUE"),
                  .CLKOUT1_DIVIDE(RXCLK_DIVIDE),
                  .CLKOUT1_USE_FINE_PS("TRUE"),
                  .CLKOUT0_DIVIDE_F(RXCLKx2_DIVIDE),
                  .CLKOUT0_USE_FINE_PS("TRUE"))
        u_rxclk_mmcm(.CLKIN1(rxclk_in),
                     .CLKFBIN(rxclk_fb_bufg),
                     .PWRDWN(1'b0),
                     .CLKFBOUT(rxclk_fb_to_bufg),
                     .CLKOUT0(rxclk_x2_to_bufg),
                     .CLKOUT1(rxclk_to_bufg),
                     .CLKOUT2(rxclk_x3_to_bufg),
                     .CLKOUT3(clk300_to_bufg),
                     .RST(rst_i),
                     .LOCKED(locked_o),
                     .PSCLK(ps_clk_i),
                     .PSEN(ps_en_i),
                     .PSINCDEC(1'b1),
                     .PSDONE(ps_done_o));    

    // phase track
    reg rxclk_toggle = 0;
    (* ASYNC_REG = "TRUE" *)
    reg [2:0] rxclk_toggle_x3_cap = {3{1'b0}};
    reg rxclk_ce = 0;
    
    // sequence
    //      rxclkx3  rxclk   toggle  toggle_x3[0] toggle_x3[1] toggle_x3[2] rxclk_ce <= toggle_x3[1] ^ toggle_x3[2]
    // x    0        0       0       0            0            0            0
    // 0    1        0       0       0            0            0            0
    // 0    0        0       0       0            0            0            0
    // 1    1        1       1       0            0            0            0
    // 1    0        1       1       0            0            0            0
    // 2    1        1       1       1            0            0            0
    // 2    0        0       1       1            0            0            0
    // 3    1        0       1       1            1            0            0
    // 3    0        0       1       1            1            0            0
    // 4    1        1       0       1            1            1            1
    // 4    0        1       0       1            1            1            1
    // 5    1        1       0       0            1            1            0
    // 5    0        0       0       0            1            1            0
    // 6    1        0       0       0            0            1            0
    // 6    0        0       0       0            0            1            0
    // 7    1        1       1       0            0            0            1
    // 7    0        1       1       0            0            0            1

    // If rxclk_ce is used as the enable, the data will be delayed by 1/3rd of an RXCLK period.
    always @(posedge rxclk_o) rxclk_toggle <= ~rxclk_toggle;
    always @(posedge rxclk_x3_o) begin
        rxclk_toggle_x3_cap <= { rxclk_toggle_x3_cap[1:0], rxclk_toggle };
        rxclk_ce <= rxclk_toggle_x3_cap[1] ^ rxclk_toggle_x3_cap[0];
    end
    
    assign rxclk_ce_o = rxclk_ce;
    
endmodule
