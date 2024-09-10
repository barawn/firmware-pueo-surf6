`timescale 1ns / 1ps
module pueo_uram_v3_tb;
    wire syncclk;
    tb_rclk #(.PERIOD(8)) u_syncclk(.clk(syncclk));
    reg syncclk_phase = 0;
    always @(posedge syncclk) syncclk_phase <= ~syncclk_phase;

    reg aclk = 0;
    reg aclk_sync = 0;
    reg memclk = 0;
    reg memclk_sync = 0;
    localparam real ACLK_HALFPER = 8.0/6.0;
    always @(posedge syncclk) begin
        aclk <= 1;
        #(ACLK_HALFPER) aclk <= 0;
        
        #(ACLK_HALFPER) aclk <= 1;
        #(ACLK_HALFPER) aclk <= 0;

        #(ACLK_HALFPER) aclk <= 1;
        #(ACLK_HALFPER) aclk <= 0;
    end 
    always @(posedge syncclk) begin
        #0.1 aclk_sync <= 1;
        @(posedge aclk);
        #0.1 aclk_sync <= 0;
    end
    always @(posedge syncclk) begin
        memclk <= 1;
        #(8/8) memclk <= 0;
        
        #(8/8) memclk <= 1;
        #(8/8) memclk <= 0;

        #(8/8) memclk <= 1;
        #(8/8) memclk <= 0;

        #(8/8) memclk <= 1;
        #(8/8) memclk <= 0;
    end
    always @(posedge syncclk) begin
        #0.1 memclk_sync <= 1;
        @(posedge memclk);
        #0.1 memclk_sync <= 0;    
    end
    
    // giant ass data array
    reg [11:0] data_in[7:0][7:0];
    wire [11:0] data_out[7:0][5:0];
    wire [12*8*8-1:0] data_vec;
    wire [12*8*6-1:0] dout_vec;
    wire [7:0] dout_valid;
    generate
        genvar i,j,k;
        for (i=0;i<8;i=i+1) begin : CH
            for (j=0;j<8;j=j+1) begin : SM
                assign data_vec[12*8*i + 12*j +: 12] = data_in[i][j];                
            end
            for (k=0;k<6;k=k+1) begin : MSM
                assign data_out[i][k] = dout_vec[12*6*i + 12*k +: 12];
            end
        end
    endgenerate
    integer ii,jj;
    initial begin
        for (ii=0;ii<8;ii=ii+1) begin
            for (jj=0;jj<8;jj=jj+1) begin
                data_in[ii][jj] <= {12{1'b0}};
            end
        end
    end
    
    reg memclk_reset = 0;
    reg ifclk_reset = 0;
    
    reg aclk_reset = 0;
    reg [15:0] addr_tdata = {16{1'b0}};
    reg        addr_tvalid = 1'b0;
    wire       addr_tready;
    wire       begin_readout;
    pueo_uram_v4 #(.SCRAMBLE_OPT("TRUE"))
        uut(.aclk(aclk),
            .aclk_rst_i(aclk_reset),
            .aclk_sync_i(aclk_sync),
            .memclk(memclk),
            .memclk_rst_i(memclk_reset),
            .memclk_sync_i(memclk_sync),
            .dat_i(data_vec),
            .begin_o(begin_readout),
            .dat_o(dout_vec),
            .dat_valid_o(dout_valid),
            .s_axis_tdata(addr_tdata),
            .s_axis_tvalid(addr_tvalid),
            .s_axis_tready(addr_tready));   
    
    wire [7:0]  ev_tdata;
    wire        ev_tvalid;
    wire        ev_tlast;
    
    reg [14:0] trig_time = {15{1'b0}};
    reg [15:0] trig_num = {16{1'b0}};
    reg        trig_valid = 0;
    
    reg [7:0]  fw_dat = {8{1'b0}};
    reg        fw_load = 0;
    reg        fw_wr = 0;
    
    uram_event_buffer_v3 u_evbuf( .memclk_i(memclk),
                               .memclk_rst_i(memclk_reset),
                               .ifclk_i(syncclk),
                               .ifclk_rst_i(ifclk_reset),
                               .begin_i(begin_readout),
                               .dat_i(dout_vec),
                               .dat_valid_i(dout_valid),
                               .trig_time_i(trig_time),
                               .event_no_i(trig_num),
                               .trig_valid_i(trig_valid),
                               .dout_data_o(ev_tdata),
                               .dout_data_valid_o(ev_tvalid),
                               .dout_data_phase_i(syncclk_phase),
                               .dout_data_last_o(ev_tlast),
                               .fw_dat_i(fw_dat),
                               .fw_load_i(fw_load),
                               .fw_wr_i(fw_wr)
                               );

    integer c,s;
    reg running = 0;
    always @(posedge aclk) begin
        if (aclk_reset) begin
            for (c=0;c<8;c=c+1) begin
                for (s=0;s<8;s=s+1) begin
                    data_in[c][s] <= ((c%4)<<8)+s;
                end
            end
            running <= 1;
        end
        if (running) begin
            for (c=0;c<8;c=c+1) begin
                for (s=0;s<8;s=s+1) begin
                    data_in[c][s] <= ((data_in[c][s] + 8) & 12'h0FF) | (data_in[c][s] & 12'hF00);
                end
            end
        end
    end
    
    task fw_write;
        input [7:0] dat;
        begin
            @(posedge syncclk);
            #1 fw_dat = dat;
               fw_wr = 1;
            @(posedge syncclk);
            #1 fw_wr = 0;
        end
    endtask
                
    initial begin
        #500;
        
//        @(posedge syncclk);
//        #1 fw_load = 1;
//        #100;
//        fw_write(8'h12);
//        fw_write(8'h34);
//        fw_write(8'h56);
//        fw_write(8'h78);
//        fw_write(8'h9A);
//        fw_write(8'hBC);
//        fw_write(8'hDE);
//        fw_write(8'hF0);
        
//        #500;
        
        
            
        #100;
        @(posedge aclk);
        #1 aclk_reset = 1;
        @(posedge aclk);
        #1 aclk_reset = 0;
        
        #1000;
        @(posedge memclk);
        #0.1 addr_tdata = 16'h0004;
        addr_tvalid = 1'b1;
        @(posedge memclk);
        while (!addr_tready) @(posedge memclk);
        #0.1 addr_tvalid = 1'b0;        
        @(posedge memclk);
        #0.1 trig_time = 55; trig_num = 1; trig_valid = 1;
        @(posedge memclk);
        #0.1 trig_valid = 0;
        
    end
    
endmodule
