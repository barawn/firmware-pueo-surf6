`timescale 1ns / 1ps
// Factored out clock generation.
module clock_generator #(parameter MODE = "PLL")(
        input aclk_in_i,
        input aclk_i,
        input rst_i,
        output ifclk_o,
        output ifclk_x2_o,
        output memclk_o,
        output locked_o
    );
    
    generate
        if (MODE == "PLL") begin : PLL
            wire ifclk_locked;
            wire memclk_locked;
            ifclk_pll u_ifclk(.clk_in1(aclk_in_i),.reset(rst_i),
                              .clk_out1(ifclk_o),
                              .clk_out2(ifclk_x2_o),
                              .locked(ifclk_locked));
            memclk_pll u_memclk(.clk_in1(aclk_in_i),.reset(rst_i),
                                .clk_out1(memclk_o),
                                .locked(memclk_locked));                      
        
            assign locked_o = memclk_locked && ifclk_locked;
        end
    endgenerate

endmodule
