`timescale 1ns / 1ps
`include "interfaces.vh"
// Wrapper for the board manager interface to directly adapt it to WISHBONE.
// Or at least, the semi-wishbone-y type interface we tend to use a lot.
module boardman_wrapper(
        input wb_clk_i,
        input wb_rst_i,
        `HOST_NAMED_PORTS_WB_IF( wb_ , 22, 32 ),
        // if burst bit is set, this controls the type of access
        input [1:0] burst_size_i,
        
        // address input if used
        input [7:0] address_i,
        
        input RX,
        output TX
    );
    
    parameter SIMULATION = "FALSE";
    parameter CLOCK_RATE = 40000000;
    parameter BAUD_RATE = 115200;
    parameter USE_ADDRESS = "FALSE";
    
    assign wb_adr_o[1:0] = 2'b00;
    assign wb_cyc_o = wb_stb_o;
    // v1/v2 can be swapped freely here for checking
    boardman_interface_v2 #(.SIMULATION(SIMULATION),
                         .CLOCK_RATE(CLOCK_RATE),
                         .BAUD_RATE(BAUD_RATE),
                         .USE_ADDRESS(USE_ADDRESS),
                         .DEBUG("FALSE"))
        u_dev(.clk(wb_clk_i),
              .rst(wb_rst_i),
              .adr_o(wb_adr_o[21:2]),
              .dat_o(wb_dat_o),
              .dat_i(wb_dat_i),
              .en_o(wb_stb_o),
              .wr_o(wb_we_o),
              .wstrb_o(wb_sel_o),
              .ack_i(wb_ack_i || wb_rty_i || wb_err_i),
              .burst_size_i(burst_size_i),
              
              .address_i(address_i),
              
              .BM_RX(RX),
              .BM_TX(TX));           
endmodule
