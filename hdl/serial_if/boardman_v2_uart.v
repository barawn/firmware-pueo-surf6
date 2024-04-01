`timescale 1ns / 1ps
`include "interfaces.vh"

// contains all of the uart-y stuff
module boardman_v2_uart(
        input clk,
        input rst,
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_axis_ , 8 ),        
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_axis_ , 8 ),
        
        input RX,
        output TX);

    parameter CLOCK_RATE = 100000000;
    parameter BAUD_RATE = 1000000;    

    /// BAUD RATE GENERATION   
    localparam ACC_BITS = 10;
    localparam real CLOCK_REAL = CLOCK_RATE;
    localparam real BAUD_REAL_X16 = BAUD_RATE*16;
    localparam real BAUD_DIVIDE = CLOCK_REAL/BAUD_REAL_X16;
    localparam real ACC_MAX = (1 << ACC_BITS);
    localparam real ACC_VAL = ACC_MAX/BAUD_DIVIDE;
    localparam ACC_VAL_X2 = ACC_VAL*2;
    // get a fixed bit value here
    localparam [10:0] BRG_ACCUMULATOR_VALUE_X2 = ACC_VAL_X2;
    // this rounds the above. For 1 MBaud this should be 164.
    localparam [9:0] BRG_ACCUMULATOR_VALUE = BRG_ACCUMULATOR_VALUE_X2[10:1] + BRG_ACCUMULATOR_VALUE_X2[0];
    reg [10:0] acc = {11{1'b0}};
    always @(posedge clk) begin
        acc <= acc[9:0] + BRG_ACCUMULATOR_VALUE;
    end
    wire en_16x_baud = acc[10];

    wire tx_full;

    uart_rx6 rx(.clk(clk),.en_16_x_baud(en_16x_baud),
                .buffer_read(m_axis_tready && m_axis_tvalid),
                .buffer_reset(rst),
                .buffer_data_present(m_axis_tvalid),.data_out(m_axis_tdata),
                .serial_in(RX));

    uart_tx6 tx(.clk(clk),.en_16_x_baud(en_16x_baud),
                .buffer_write(s_axis_tready && s_axis_tvalid),
                .buffer_reset(rst),
                .buffer_full(tx_full),.data_in(s_axis_tdata),
                .serial_out(TX));

    assign s_axis_tready = !tx_full;                    
        
endmodule