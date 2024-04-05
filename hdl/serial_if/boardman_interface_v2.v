`timescale 1ns / 1ps
`include "interfaces.vh"
// The v2 interface modularizes a lot of the internals
// so they can be tested independently. Same interface
// as v1 though.
module boardman_interface_v2(
        input clk,
        input rst,
        // we lose 23 to write address
        // we lose 22 to board manager
        // leaves 21:0, or 22 bits.
        // This is a byte address, so it gives us an address space of 4 MiB.
        // We output a 32-bit address so we also lose 1:0, leaving us
        // with 19:0.
        output [19:0] adr_o,
        output [31:0] dat_o,
        input  [31:0] dat_i,
        output        en_o,
        output        wr_o,
        output [3:0]  wstrb_o,
        input         ack_i,
        
        // 00: in burst mode, these are byte accesses
        // 01: in burst mode, these are word accesses
        // 10: in burst mode, these are qword accesses
        // 11: reserved
        input [1:0]   burst_size_i,
        
        // address input, if used
        input [7:0] address_i,
        
        input BM_RX,
        output BM_TX        
    );
    parameter SIMULATION = "FALSE";    
    parameter DEBUG = "FALSE";
    parameter USE_ADDRESS = "FALSE";
            
    parameter CLOCK_RATE = 100000000;
    parameter BAUD_RATE = 1000000;    
       

    // UART-to-COBS
    `DEFINE_AXI4S_MIN_IF( cobs_rx_ , 8 );
    wire cobs_rx_tlast = (cobs_rx_tdata == 8'h00);
    `DEFINE_AXI4S_MIN_IF( cobs_tx_ , 8 );
    
    // COBS-to-SM
    `DEFINE_AXI4S_MIN_IF( axis_rx_ , 8 );
    wire axis_rx_tlast;
    wire axis_rx_tuser;
    `DEFINE_AXI4S_MIN_IF( axis_tx_ , 8 );
    wire axis_tx_tlast;
            
    // UART
    boardman_v2_uart #(.CLOCK_RATE(CLOCK_RATE),
                       .BAUD_RATE(BAUD_RATE))
        u_uart(.clk(clk),.rst(rst),
               `CONNECT_AXI4S_MIN_IF( s_axis_ , cobs_tx_ ),
               `CONNECT_AXI4S_MIN_IF( m_axis_ , cobs_rx_ ),
               .RX(BM_RX),
               .TX(BM_TX));                       
    // through COBS encode/decode
    boardman_v2_cobs u_cobs( .clk(clk),.rst(rst),
                             `CONNECT_AXI4S_MIN_IF( s_uart_rx_ , cobs_rx_  ),
                             .s_uart_rx_tlast( cobs_rx_tlast ),
                             `CONNECT_AXI4S_MIN_IF( m_uart_tx_ , cobs_tx_ ),
                             
                             `CONNECT_AXI4S_MIN_IF( m_axis_rx_ , axis_rx_ ),
                             .m_axis_rx_tlast( axis_rx_tlast ),
                             .m_axis_rx_tuser( axis_rx_tuser ),
                             `CONNECT_AXI4S_MIN_IF( s_axis_tx_ , axis_tx_ ),
                             .s_axis_tx_tlast( axis_tx_tlast ));
    
    boardman_ila u_ila(.clk(clk),
                   .probe0( cobs_rx_tdata ),
                   .probe1( cobs_rx_tvalid ),
                   .probe2( cobs_rx_tready ),
                   .probe3( axis_rx_tdata ),
                   .probe4( axis_rx_tvalid ),
                   .probe5( axis_rx_tready ),
                   .probe6( axis_tx_tdata ),
                   .probe7( axis_tx_tvalid ),
                   .probe8( axis_tx_tready ));

    // to state machine
    boardman_v2_sm #(.DEBUG(DEBUG),
                     .SIMULATION(SIMULATION),
                     .USE_ADDRESS(USE_ADDRESS))
        u_sm(.clk(clk),.rst(rst),
             .adr_o(adr_o),
             .dat_o(dat_o),
             .dat_i(dat_i),
             .en_o(en_o),
             .wr_o(wr_o),
             .wstrb_o(wstrb_o),
             .ack_i(ack_i),
             .burst_size_i(burst_size_i),
             .address_i(address_i),
             `CONNECT_AXI4S_MIN_IF( axis_rx_ , axis_rx_ ),
             .axis_rx_tlast(axis_rx_tlast),
             .axis_rx_tuser(axis_rx_tuser),
             `CONNECT_AXI4S_MIN_IF( axis_tx_ , axis_tx_ ),
             .axis_tx_tlast(axis_tx_tlast));                      
                                                    
endmodule
