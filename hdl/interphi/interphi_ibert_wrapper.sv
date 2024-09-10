`timescale 1ns / 1ps
// this wraps the bizarre interphi ibert 
// When you use clock distribution, the IBERT takes in BOTH
// refclks from the quad you use and calls them
// gty_refclk0p_i[0] -> refclk0
// gty_refclk0n_i[0] |
// gty_refclk1p_i[0] -> refclk1
// gty_refclk1n_i[0] |
// 
// In the end only one of them gets used.
// We use refclk1 (gtp_mgtclk_i)
// but the GTYE4_COMMON apparently wants both,
// so we give it gtp_mgtaltclk_i
module interphi_ibert_wrapper(
        input [7:0] INTERPHI_RXP,
        input [7:0] INTERPHI_RXN,
        output [7:0] INTERPHI_TXP,
        output [7:0] INTERPHI_TXN,
        input gtp_clk_i,
        input gtp_mgtclk_i,
        input gtp_mgtaltclk_i
    );
    parameter SPEED = "10G";
    // the way the example designs hook things up is:
    // clk is gty_sysclk_i which is the output of a BUFG_GT
    // taking gty_odiv2_1_i[0] which is the ODIV2 output
    // of gty_refclk1p_i[0]/gty_refclk1p_i[1]
    // The REFCLKS USED is only 1 though
    // so this is F28/F29 which is B129 clock 1 as expected.
    //
    // so that's our gtp_clk.
    // gtp_mgtclk_i is the O output of the IBUFDS_GTE4 we're using
    // gtp_mgtaltclk_i is the O output of the IBUFDS_GTE4 we are NOT using
    // SO BIZARRE
    
    
    // we also have some goofy extras
    wire [1:0] gty_qrefclk0_i;
    wire [1:0] gty_qrefclk1_i;
    wire [1:0] gty_qnorthrefclk0_i;
    wire [1:0] gty_qnorthrefclk1_i;
    wire [1:0] gty_qsouthrefclk0_i;
    wire [1:0] gty_qsouthrefclk1_i;
    // NO CLUE ON THESE
    wire [1:0] gty_qrefclk00_i;
    wire [1:0] gty_qrefclk10_i;
    wire [1:0] gty_qrefclk01_i;
    wire [1:0] gty_qrefclk11_i;
    wire [1:0] gty_qnorthrefclk00_i;
    wire [1:0] gty_qnorthrefclk10_i;
    wire [1:0] gty_qnorthrefclk01_i;
    wire [1:0] gty_qnorthrefclk11_i;
    wire [1:0] gty_qsouthrefclk00_i;
    wire [1:0] gty_qsouthrefclk10_i;
    wire [1:0] gty_qsouthrefclk01_i;
    wire [1:0] gty_qsouthrefclk11_i;
    // in the exdes
    // there's also gty_refclk0_i/gty_refclk1_i
    // These are the O outputs of the IBUFDS_GTE
    // and gty_odiv2_0_i/gty_odv2_1_i (same deal)
    // then gty_sysclk_i is the BUFG_GT output of that.
    // Those are done in the top level module for us
    
    // These are for quad 0, which DOES NOT have a real clock input.
    assign gty_qrefclk0_i[0] = 1'b0;
    assign gty_qrefclk1_i[0] = 1'b0;
    assign gty_qnorthrefclk0_i[0] = 1'b0;
    assign gty_qnorthrefclk1_i[0] = 1'b0;
    assign gty_qsouthrefclk0_i[0] = 1'b0;
    assign gty_qsouthrefclk1_i[0] = gtp_mgtclk_i; // was gty_refclk1_i[0]: O output of IBUFDS
    //GTYE4_COMMON clock connection
    assign gty_qrefclk00_i[0] = 1'b0;
    assign gty_qrefclk10_i[0] = 1'b0;
    assign gty_qrefclk01_i[0] = 1'b0;
    assign gty_qrefclk11_i[0] = 1'b0;
    assign gty_qnorthrefclk00_i[0] = 1'b0;
    assign gty_qnorthrefclk10_i[0] = 1'b0;
    assign gty_qnorthrefclk01_i[0] = 1'b0;
    assign gty_qnorthrefclk11_i[0] = 1'b0;
    assign gty_qsouthrefclk00_i[0] = 1'b0;
    assign gty_qsouthrefclk10_i[0] = gtp_mgtclk_i; // was gty_refclk1_i[0]
    assign gty_qsouthrefclk01_i[0] = 1'b0;
    assign gty_qsouthrefclk11_i[0] = 1'b0;    
    
    // This is for quad 1, which DOES have a real clock input
    assign gty_qrefclk0_i[1] = gtp_mgtaltclk_i;
    assign gty_qrefclk1_i[1] = gtp_mgtclk_i;
    assign gty_qnorthrefclk0_i[1] = 1'b0;
    assign gty_qnorthrefclk1_i[1] = 1'b0;
    assign gty_qsouthrefclk0_i[1] = 1'b0;
    assign gty_qsouthrefclk1_i[1] = 1'b0;
    //GTYE4_COMMON clock connection
    assign gty_qrefclk00_i[1] = gtp_mgtaltclk_i;
    assign gty_qrefclk10_i[1] = gtp_mgtclk_i;
    assign gty_qrefclk01_i[1] = 1'b0;
    assign gty_qrefclk11_i[1] = 1'b0;  
    assign gty_qnorthrefclk00_i[1] = 1'b0;
    assign gty_qnorthrefclk10_i[1] = 1'b0;
    assign gty_qnorthrefclk01_i[1] = 1'b0;
    assign gty_qnorthrefclk11_i[1] = 1'b0;  
    assign gty_qsouthrefclk00_i[1] = 1'b0;
    assign gty_qsouthrefclk10_i[1] = 1'b0;  
    assign gty_qsouthrefclk01_i[1] = 1'b0;
    assign gty_qsouthrefclk11_i[1] = 1'b0; 
         
    generate
        if (SPEED == "10G") begin : GIG10
            interphi_ibert10 u_ibert(.rxn_i(INTERPHI_RXN),
                                   .rxp_i(INTERPHI_RXP),
                                   .txp_o(INTERPHI_TXP),
                                   .txn_o(INTERPHI_TXN),
                                   .clk(gtp_clk_i),
                                  .gtrefclk0_i(gty_qrefclk0_i),
                                  .gtrefclk1_i(gty_qrefclk1_i),
                                  .gtnorthrefclk0_i(gty_qnorthrefclk0_i),
                                  .gtnorthrefclk1_i(gty_qnorthrefclk1_i),
                                  .gtsouthrefclk0_i(gty_qsouthrefclk0_i),
                                  .gtsouthrefclk1_i(gty_qsouthrefclk1_i),
                                  .gtrefclk00_i(gty_qrefclk00_i),
                                  .gtrefclk10_i(gty_qrefclk10_i),
                                  .gtrefclk01_i(gty_qrefclk01_i),
                                  .gtrefclk11_i(gty_qrefclk11_i),
                                  .gtnorthrefclk00_i(gty_qnorthrefclk00_i),
                                  .gtnorthrefclk10_i(gty_qnorthrefclk10_i),
                                  .gtnorthrefclk01_i(gty_qnorthrefclk01_i),
                                  .gtnorthrefclk11_i(gty_qnorthrefclk11_i),
                                  .gtsouthrefclk00_i(gty_qsouthrefclk00_i),
                                  .gtsouthrefclk10_i(gty_qsouthrefclk10_i),
                                  .gtsouthrefclk01_i(gty_qsouthrefclk01_i),
                                  .gtsouthrefclk11_i(gty_qsouthrefclk11_i)
                                );
        end else begin : GIG20                  
            interphi_ibert u_ibert(.rxn_i(INTERPHI_RXN),
                                   .rxp_i(INTERPHI_RXP),
                                   .txp_o(INTERPHI_TXP),
                                   .txn_o(INTERPHI_TXN),
                                   .clk(gtp_clk_i),
                                  .gtrefclk0_i(gty_qrefclk0_i),
                                  .gtrefclk1_i(gty_qrefclk1_i),
                                  .gtnorthrefclk0_i(gty_qnorthrefclk0_i),
                                  .gtnorthrefclk1_i(gty_qnorthrefclk1_i),
                                  .gtsouthrefclk0_i(gty_qsouthrefclk0_i),
                                  .gtsouthrefclk1_i(gty_qsouthrefclk1_i),
                                  .gtrefclk00_i(gty_qrefclk00_i),
                                  .gtrefclk10_i(gty_qrefclk10_i),
                                  .gtrefclk01_i(gty_qrefclk01_i),
                                  .gtrefclk11_i(gty_qrefclk11_i),
                                  .gtnorthrefclk00_i(gty_qnorthrefclk00_i),
                                  .gtnorthrefclk10_i(gty_qnorthrefclk10_i),
                                  .gtnorthrefclk01_i(gty_qnorthrefclk01_i),
                                  .gtnorthrefclk11_i(gty_qnorthrefclk11_i),
                                  .gtsouthrefclk00_i(gty_qsouthrefclk00_i),
                                  .gtsouthrefclk10_i(gty_qsouthrefclk10_i),
                                  .gtsouthrefclk01_i(gty_qsouthrefclk01_i),
                                  .gtsouthrefclk11_i(gty_qsouthrefclk11_i)
                                );
        end
    endgenerate
endmodule
