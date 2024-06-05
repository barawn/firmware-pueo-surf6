`timescale 1ns / 1ps

module pueo_readout_tb;

    // run at 3 GHz to begin
    reg sclk = 0;
    always #0.166 sclk = ~sclk;
    
    // 375 is 1/8th so toggle every 4
    reg [1:0] aclk_counter = {2{1'b0}};
    always @(posedge sclk) aclk_counter <= aclk_counter + 1;
    reg aclk = 1;
    always @(posedge sclk) if (aclk_counter == 2'b11) aclk <= ~aclk;
    // memclk is 500 so toggle every 3
    reg [1:0] memclk_counter = {2{1'b0}};
    always @(posedge sclk) if (memclk_counter == 2) memclk_counter <= 2'b00; 
                           else memclk_counter <= memclk_counter + 1;
    reg memclk = 1;
    always @(posedge sclk) if (memclk_counter == 2) memclk <= ~memclk;
    
    // syncclk is 1/12th so toggle every 6
    reg [3:0] syncclk_counter = {4{1'b00}};
    always @(posedge sclk) if (syncclk_counter == 11) syncclk_counter <= {4{1'b0}};
                           else syncclk_counter <= syncclk_counter + 1;
    reg syncclk = 1;
    always @(posedge sclk) if (syncclk_counter == 11) syncclk <= ~syncclk;
    
    wire aclk_sync;
    wire memclk_sync;
    
    pueo_clk_phase u_sync(.aclk(aclk),
                          .memclk(memclk),
                          .syncclk(syncclk),
                          .aclk_sync_o(aclk_sync),
                          .memclk_sync_o(memclk_sync));
    
    reg [15:0] dat = {16{1'b0}};
    reg [16*7-1:0] dat_store = {16*7{1'b0}};
    reg [16*8-1:0] dat_aclk = {16*8{1'b0}};
    // The incoming data has dat[0] being the oldest. So we need to fill *downward*.
    always @(posedge sclk) begin
        dat <= dat + 16;
        dat_store[6*16 +: 16] <= dat;
        dat_store[5*16 +: 16] <= dat_store[6*16 +: 16];
        dat_store[4*16 +: 16] <= dat_store[5*16 +: 16];
        dat_store[3*16 +: 16] <= dat_store[4*16 +: 16];
        dat_store[2*16 +: 16] <= dat_store[3*16 +: 16];
        dat_store[1*16 +: 16] <= dat_store[2*16 +: 16];
        dat_store[0*16 +: 16] <= dat_store[1*16 +: 16];
    end
    always @(posedge aclk) dat_aclk <= { dat, dat_store };
    
    reg aclk_rst = 0;    
    reg [15:0] addr_request = {16{1'b0}};
    reg addr_request_valid = 0;
    wire addr_request_ready;
    wire [6*12-1:0] data_out;
    wire data_out_valid;

    // Drop the unused bits, and buffer.
    reg [95:0] dat_rereg = {96{1'b0}};
    generate
        genvar j;
        for (j=0;j<8;j=j+1) begin : SRR
            always @(posedge aclk) begin : RRL
                dat_rereg[12*j +: 12] <= dat_aclk[16*j+4 +: 12];
            end
        end
    endgenerate
        
    pueo_uram u_uram(.aclk(aclk),
                     .aclk_sync_i(aclk_sync),
                     .aclk_rst_i(aclk_rst),
                     .dat_i(dat_rereg),
                     .memclk(memclk),
                     .memclk_sync_i(memclk_sync),
                     .s_axis_tdata(addr_request),
                     .s_axis_tvalid(addr_request_valid),
                     .s_axis_tready(addr_request_ready),
                     .m_axis_tdata(data_out),
                     .m_axis_tvalid(data_out_valid),
                     .m_axis_tready(1'b1));

    initial begin
        #100;
        @(posedge aclk);
        #1 aclk_rst = 1;
        @(posedge aclk);
        #1 aclk_rst = 0;
        #2000;
        @(posedge memclk);
        #1 addr_request_valid = 1;
        while (!addr_request_ready) @(posedge memclk);
        #1 addr_request_valid = 0;
    end
                     
endmodule
