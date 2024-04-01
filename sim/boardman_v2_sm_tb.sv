`timescale 1ns / 1ps

module boardman_v2_sm_tb;

    wire clk;
    tb_rclk #(.PERIOD(8.0)) u_clk(.clk(clk));
    
    wire en;
    wire wr;
    wire wstrb;
    reg ack = 0;
    always @(posedge clk) ack <= en;
    
    reg [31:0] dat_out = 32'h12345678;
    wire [31:0] dat_in;
    wire [19:0] adr;
    wire [3:0] wstrb;
    
    reg [7:0] address = 8'd0;
    wire [1:0] burst_size = 2'b00;
    
    wire axis_rx_tready;
    reg [7:0] axis_rx_tdata = {8{1'b0}};
    reg axis_rx_tvalid = 0;
    reg axis_rx_tlast = 0;
    
    wire axis_tx_tvalid;
    wire [7:0] axis_tx_tdata;
    wire axis_tx_tready = 1'b1;
    
    boardman_v2_sm #(.USE_ADDRESS("TRUE")) uut(.clk(clk),
                                               .rst(1'b0),
                                               .adr_o(adr),
                                               .dat_o(dat_in),
                                               .dat_i(dat_out),
                                               .en_o(en),
                                               .wr_o(wr),
                                               .wstrb_o(wstrb),
                                               .ack_i(ack && en),
                                               .burst_size_i(burst_size),
                                               .address_i(address),
                                               .axis_rx_tdata(axis_rx_tdata),
                                               .axis_rx_tvalid(axis_rx_tvalid),
                                               .axis_rx_tready(axis_rx_tready),
                                               .axis_rx_tuser(1'b0),
                                               .axis_rx_tlast(axis_rx_tlast),
                                               .axis_tx_tdata(axis_tx_tdata),
                                               .axis_tx_tvalid(axis_tx_tvalid),
                                               .axis_tx_tready(axis_tx_tready));
    
    task bm_write;
        input [7:0] this_addr;
        begin
            @(posedge clk); #1;
            axis_rx_tvalid = 1;
            axis_rx_tdata = this_addr;
            axis_rx_tlast = 0;
            while (!axis_rx_tready) @(posedge clk);
            @(posedge clk); axis_rx_tdata = 8'h10;
            while (!axis_rx_tready) @(posedge clk);
            @(posedge clk); axis_rx_tdata = 8'h00;
            while (!axis_rx_tready) @(posedge clk);
            @(posedge clk); axis_rx_tdata = 8'h00;
            while (!axis_rx_tready) @(posedge clk);
            @(posedge clk); axis_rx_tdata = 8'h03; axis_rx_tlast = 1;
            while (!axis_rx_tready) @(posedge clk);
            #1 axis_rx_tvalid = 1'b0;
        end
    endtask
    
    initial begin
        #150;
        bm_write(8'h00);
        #1000;
        bm_write(8'h01);
        #1000;                               
    end
endmodule