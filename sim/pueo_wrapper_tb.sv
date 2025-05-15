`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/14/2025 10:40:46 PM
// Design Name: 
// Module Name: pueo_wrapper_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module pueo_wrapper_tb;
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
    
    reg run_rst = 0;
    reg run_stop = 0;
    
    reg [15:0] trig_time = {16{1'b0}};
    reg trig_time_valid = 0;
    
    reg dout_data_phase = 0;
    wire [7:0] dout_data;
    wire dout_data_valid;
    
    always @(posedge syncclk) dout_data_phase <= #0.1 ~dout_data_phase;
    
    pueo_wrapper uut(.aclk_i(aclk),
                     .aclk_sync_i(aclk_sync),
                     .memclk_i(memclk),
                     .memclk_sync_i(memclk_sync),
                     .ifclk_i(syncclk),
                     .run_rst_i(run_rst),
                     .run_stop_i(run_stop),
                     .ch_dat_i(data_vec),
                     .trig_time_i(trig_time),
                     .trig_time_valid_i(trig_time_valid),
                     
                     .dout_data_phase_i(dout_data_phase),
                     .dout_data_o(dout_data),
                     .dout_data_valid_o(dout_data_valid),
                     
                     .fw_loading_i(1'b0),
                     .fw_tdata(8'h00),
                     .fw_tvalid(1'b0),
                     .fw_tready(),
                     .fw_mark_i(2'b00),
                     .fwmon_wr_o());

    reg aclk_reset = 0;

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

    initial begin
        #500;
        @(posedge aclk);
        #1 aclk_reset = 1;
        @(posedge aclk);
        #1 aclk_reset = 0;

        @(posedge syncclk);
        #1 run_rst = 1;
        @(posedge syncclk);
        #1 run_rst = 0;
        
        #1000;
        @(posedge aclk);
        // These HAVE to be multiples of 4!
        #0.1 trig_time = 12; trig_time_valid = 1;
        @(posedge aclk);
        #0.1 trig_time_valid = 0;            
    end
        
endmodule
