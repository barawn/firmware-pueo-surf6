`timescale 1ns / 1ps
`include "interfaces.vh"
// This is the PUEO command wrapper.
// It's derived from the boardman wrapper, but
// it has multiple command inputs.
// The command inputs are multiplexed by an AXI4-Stream
// switch which multiplexes the requests.
module pueo_command_wrapper(
        input wb_clk_i,
        input wb_rst_i,
        `HOST_NAMED_PORTS_WB_IF( wb_ , 22, 32 ),
        // if burst bit is set, this controls the type of access
        input [1:0] burst_size_i,
        
        // address input if used
        input [7:0] address_i,
        // Command processor path
        input aclk_i,
        input cmdproc_rst_i,
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( cmdproc_ , 8),
        input cmdproc_tlast,
        `HOST_NAMED_PORTS_AXI4S_MIN_IF(cmdresp_ , 8),
        output cmdresp_tlast,
        // UART path
        input RX,
        output TX
    );
    
    parameter SIMULATION = "FALSE";
    parameter CLOCK_RATE = 40000000;
    parameter BAUD_RATE = 115200;
    parameter USE_ADDRESS = "FALSE";
    parameter DEBUG = "TRUE";
    
    assign wb_adr_o[1:0] = 2'b00;
    assign wb_cyc_o = wb_stb_o;

    // We don't use the interface - we use the bits and pieces.
    // Outbound packets are always statefully complete.
    // If we get crap inbound, we re-arbitrate.
    localparam NUM_BM_SOURCES = 2;
    reg [NUM_BM_SOURCES-1:0] active_source = {NUM_BM_SOURCES{1'b0}};
    wire [NUM_BM_SOURCES-1:0] source_has_data;
    wire source_done;
    // our arbitration algorithm is a bit arbitrary (lol)
    // source 0 always has priority
    always @(posedge wb_clk_i) begin
        if (active_source == 2'b00 && source_has_data[0]) begin
            active_source[0] <= 1'b1;
        end else begin
            if (source_done) active_source[0] <= 1'b0;
        end
        if (active_source == 2'b00 && source_has_data[1] && !source_has_data[0]) begin
            active_source[1] <= 1'b1;
        end else begin
            if (source_done) active_source[1] <= 1'b1;
        end            
    end

    // OK, so here we define the sources.
    // this is from the BOARD MANAGER'S point of view
    `DEFINE_AXI4S_MIN_IF( source0_rx_ , 8 );
    wire source0_rx_tlast;
    wire source0_rx_tuser = 1'b0;
    `DEFINE_AXI4S_MIN_IF( source0_tx_ , 8 );
    wire source0_tx_tlast;
    
    `DEFINE_AXI4S_MIN_IF( source1_rx_ , 8 );
    wire source1_rx_tlast;
    wire source1_rx_tuser;
    `DEFINE_AXI4S_MIN_IF( source1_tx_ , 8 );
    wire source1_tx_tlast;
    
    `DEFINE_AXI4S_MIN_IF( mux_rx_ , 8 );
    wire mux_rx_tlast;
    wire mux_rx_tuser;
    `DEFINE_AXI4S_MIN_IF( mux_tx_ , 8 );
    wire mux_tx_tlast;
    
    // let's ... just do it stupidly
    // INBOUND MUX
    assign mux_rx_tdata = (active_source[1]) ? source1_rx_tdata : source0_rx_tdata;
    assign mux_rx_tvalid = (active_source[1]) ? source1_rx_tvalid : source0_rx_tvalid;
    assign source0_rx_tready = active_source[0] && mux_rx_tready;
    assign source1_rx_tready = active_source[1] && mux_rx_tready;
    assign mux_rx_tlast = (active_source[1]) ? source1_rx_tlast : source0_rx_tlast;
    assign mux_rx_tuser = (active_source[1]) ? source1_rx_tuser : source0_rx_tuser;
    
    assign source0_tx_data = mux_tx_tdata;
    assign source0_tx_tvalid = active_source[0] && mux_tx_tvalid;
    assign source0_tx_tlast = active_source[0] && mux_tx_tlast;
    assign source1_tx_tdata = mux_tx_tdata;
    assign source1_tx_tvalid = active_source[1] && mux_tx_tvalid;
    assign source1_tx_tlast = active_source[1] && mux_tx_tlast;
    assign mux_tx_tready = (active_source[1]) ? source1_tx_tready : source0_tx_tready;
    
    // ok, for right now we're just going to do a clock-cross FIFO
    // this is kinda dumb since our inputs are So Damn Slow
    // (6 ACLK clocks/byte, minimum of what, 5 bytes or so or something = 30 ACLK clocks
    // = 80 ns = 8 system clocks)
    // Maybe eventually I'll just replace this whole damn thing or something
    // with a branched state machine.
    // convert standard FIFO into axi4-stream
    wire cmdproc_fifo_full;
    assign cmdproc_tready = !cmdproc_fifo_full;
    wire cmdresp_fifo_full;
    assign source0_tx_tready = !cmdresp_fifo_full;
    cmd_rxtx_fifo u_cmdprocfifo(.wr_clk(aclk),
                                .rd_clk(wb_clk_i),
                                .rst(cmdproc_rst_i),
                                .din(cmdproc_tdata),
                                .full(cmdproc_fifo_full),
                                .wr_en(cmdproc_tvalid && cmdproc_tready),
                                .dout(source0_rx_tdata),
                                .rd_en(source0_rx_tvalid && source0_rx_tready),
                                .valid(source0_rx_tvalid));
    cmd_rxtx_fifo u_cmdrespfifo(.wr_clk(wb_clk_i),
                                .rd_clk(aclk),
                                .rst(cmdproc_rst_i),
                                .din(source0_tx_tdata),
                                .full(cmdresp_fifo_full),
                                .wr_en(source0_tx_tvalid && source0_tx_tready),
                                .dout(cmdresp_tdata),
                                .rd_en(cmdresp_tvalid && cmdresp_tready),
                                .valid(cmdresp_tvalid));    
    // now the UART...
    `DEFINE_AXI4S_MIN_IF( uart_rx_ , 8);
    `DEFINE_AXI4S_MIN_IF( uart_tx_ , 8);
    wire uart_tlast = (uart_rx_tdata == 8'h00);
    boardman_v2_uart #(.CLOCK_RATE(CLOCK_RATE),
                       .BAUD_RATE(BAUD_RATE))
        u_uart(.clk(wb_clk_i),.rst(wb_rst_i),
               `CONNECT_AXI4S_MIN_IF( m_axis_ , uart_rx_ ),
               `CONNECT_AXI4S_MIN_IF( s_axis_ , uart_tx_ ),
               .RX(RX),
               .TX(TX));
    // and COBS decode. I seriously need to work out the logic of
    // the UART module to do a COBS-integrated version.             
    boardman_v2_cobs u_cobs(.clk(wb_clk_i),.rst(rst),
                            `CONNECT_AXI4S_MIN_IF( s_uart_rx_ , uart_rx_ ),
                            .s_uart_rx_tlast( uart_tlast ),
                            `CONNECT_AXI4S_MIN_IF( m_uart_tx_ , uart_tx_ ),
                            
                            `CONNECT_AXI4S_MIN_IF( m_axis_rx_ , source1_rx_ ),
                            .m_axis_rx_tlast(source1_rx_tlast),
                            .m_axis_rx_tuser(source1_rx_tuser),
                            `CONNECT_AXI4S_MIN_IF( s_axis_tx_ , source1_tx_ ),
                            .s_axis_tx_tlast( source1_tx_tlast ));
    // and now use the v3 state machine
    assign wb_adr_o[1:0] = 2'b00;
    assign wb_cyc_o = wb_stb_o;
    boardman_v3_sm #(.DEBUG(DEBUG),
                     .SIMULATION(SIMULATION),
                     .USE_ADDRESS(USE_ADDRESS))
        u_sm(.clk(wb_clk_i),.rst(wb_rst_i),
             .adr_o(wb_adr_o[21:2]),
             .dat_o(wb_dat_o),
             .dat_i(wb_dat_i),
             .en_o(wb_stb_o),
             .wr_o(wb_we_o),
             .wstrb_o(wb_sel_o),
             .ack_i(wb_ack_i || wb_rty_i || wb_err_i),
             .burst_size_i(burst_size_i),
             .address_i(address_i),
             `CONNECT_AXI4S_MIN_IF( axis_rx_ , mux_rx_ ),
             .axis_rx_tlast(mux_rx_tlast),
             .axis_rx_tuser(mux_rx_tuser),
             `CONNECT_AXI4S_MIN_IF( axis_tx_ , mux_tx_ ),
             .axis_tx_tlast(mux_tx_tlast),
             .done_o(source_done));

endmodule
