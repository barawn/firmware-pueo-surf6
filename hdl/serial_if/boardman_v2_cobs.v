`timescale 1ns / 1ps
`include "interfaces.vh"

module boardman_v2_cobs( input clk,
                         input rst,
                         `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_uart_rx_ , 8 ),
                         input s_uart_rx_tlast,
                         `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_uart_tx_ , 8 ),
                         
                         `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_axis_rx_ , 8 ),
                         output m_axis_rx_tlast,
                         output m_axis_rx_tuser,
                         `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_axis_tx_ , 8 ),
                         input s_axis_tx_tlast );

    // Our "hard reset the interface" method: 4 null bytes (0) in a row.
    reg [1:0] null_counter = {2{1'b0}};
    reg cobs_reset = 0;
    always @(posedge clk) begin
        if (s_uart_rx_tready && s_uart_rx_tvalid) begin
            if (s_uart_rx_tdata == 8'h00) null_counter[1:0] <= null_counter[1:0] + 1;
            else null_counter <= {2{1'b0}};
        end
        if (s_uart_rx_tready && s_uart_rx_tvalid && s_uart_rx_tdata == 8'h00 && null_counter[1:0] == 2'b11) cobs_reset <= 1;
        else cobs_reset <= 0;
    end    

    axis_cobs_decode u_decoder(.clk(clk),.rst(rst || cobs_reset),
                                `CONNECT_AXI4S_MIN_IF( s_axis_ , s_uart_rx_ ),
                                .s_axis_tuser(1'b0),
                                .s_axis_tlast(s_uart_rx_tlast),
                                `CONNECT_AXI4S_MIN_IF( m_axis_ , m_axis_rx_ ),
                                .m_axis_tuser(m_axis_rx_tuser),
                                .m_axis_tlast(m_axis_rx_tlast));
    axis_cobs_encode u_encoder( .clk(clk), .rst(rst || cobs_reset),
                                `CONNECT_AXI4S_MIN_IF( s_axis_ , s_axis_tx_ ),
                                .s_axis_tuser(1'b0),
                                .s_axis_tlast(s_axis_tx_tlast),
                                `CONNECT_AXI4S_MIN_IF( m_axis_ , m_uart_tx_ ));
                         
endmodule                         