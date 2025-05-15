`timescale 1ns / 1ps
`include "interfaces.vh"
module rfdc_wrapper #(parameter DEVICE="GEN1",
                      parameter NCLKS=4,
                      parameter NCHAN=8,
                      parameter NSAMP=8,
                      parameter NBITS=12,
                      parameter DEBUG="TRUE")(
        input wb_clk_i,
        input wb_rst_i,
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 18, 32 ),
        output bridge_err_o,
        
        input aclk,
        input aresetn,
        input sysref_pl_i,
        input sysref_dac_i,
                
        input sysref_p,
        input sysref_n,
        
        // ultrastupidity
        input dac_clk_p,
        input dac_clk_n,
        input dac_out_p,
        input dac_out_n,
                
        // these vector        
        input [NCLKS-1:0] adc_clk_p,
        input [NCLKS-1:0] adc_clk_n,
        // these also vector
        input [NCHAN-1:0] adc_in_p,
        input [NCHAN-1:0] adc_in_n,
        // wacko huge vector
        output [NSAMP*NCHAN*NBITS-1:0] adc_dout        
    );

    localparam RFDC_BITS = 16;
            
    // converting from wb to axi in the dumbest way possible
    localparam FSM_BITS=2;
    localparam [FSM_BITS-1:0] IDLE = 0;
    localparam [FSM_BITS-1:0] AXI_BEGIN = 1;
    localparam [FSM_BITS-1:0] AXI_WAIT = 2;
    localparam [FSM_BITS-1:0] ACK = 3;
    reg [FSM_BITS-1:0] state = IDLE;
    
    `DEFINE_AXI4L_IF( rfdc_ , 18, 32);
    // the WB->AXI bridge is
    // assert awvalid && wvalid

    reg axi_writing = 0;
    reg axi_waddr_accepted = 0;
    reg axi_wdata_accepted = 0;
    wire axi_write_accepted = (axi_waddr_accepted && axi_wdata_accepted);
    // these two can happen in parallel
    assign rfdc_awvalid = (axi_writing && !axi_waddr_accepted);
    assign rfdc_wvalid = (axi_writing && !axi_wdata_accepted);
    wire axi_write_complete = (axi_waddr_accepted && axi_wdata_accepted);
    
    assign rfdc_bready = (state == AXI_WAIT && axi_writing);
    
    reg axi_reading = 0;
    reg axi_raddr_accepted = 0;
    assign rfdc_arvalid = (axi_reading && !axi_raddr_accepted);
    wire axi_read_complete = (axi_raddr_accepted);    
    // For the read path, we don't assert rready until ACK
    // so we don't need a register.
    assign rfdc_rready = (state == ACK && axi_reading);
    
    assign wb_ack_o = (state == ACK);
    assign wb_err_o = 1'b0;
    assign wb_rty_o = 1'b0;
    assign wb_dat_o = rfdc_rdata;
    assign rfdc_wdata = wb_dat_i;
    assign rfdc_wstrb = wb_sel_i;
    assign rfdc_awaddr = wb_adr_i;
    assign rfdc_araddr = wb_adr_i;
    
    reg bridge_err = 0;
    always @(posedge wb_clk_i) begin
        // flag a bridge error, let someone else sticky it
        if ((rfdc_bready && rfdc_bvalid && rfdc_bresp[1]) ||
            (rfdc_rready && rfdc_rvalid && rfdc_rresp[1]))
           bridge_err <= 1;
        else
           bridge_err <= 0;
           
        if (state == ACK) axi_waddr_accepted <= 0;
        else if (rfdc_awready && rfdc_awvalid) axi_waddr_accepted <= 1;
        if (state == ACK) axi_wdata_accepted <= 0;
        else if (rfdc_wready && rfdc_wvalid) axi_wdata_accepted <= 1;
        if (state == ACK) axi_raddr_accepted <= 0;
        else if (rfdc_arready && rfdc_arvalid) axi_raddr_accepted <= 1;
        
        if (state == ACK) axi_writing <= 0;
        else if (state == IDLE && wb_cyc_i && wb_stb_i && wb_we_i) axi_writing <= 1;
        if (state == ACK) axi_reading <= 0;
        else if (state == IDLE && wb_cyc_i && wb_stb_i && !wb_we_i) axi_reading <= 1;
        
        case (state)
            IDLE: if (wb_cyc_i && wb_stb_i) state <= AXI_BEGIN;
            AXI_BEGIN: if ((axi_writing && axi_write_complete) ||
                           (axi_reading && axi_read_complete)) state <= AXI_WAIT;
            // this is identical to axi_writing && rfdc_bvalid.
            // the read path waits for rvalid because it can
            AXI_WAIT: if ((rfdc_bready && rfdc_bvalid) ||
                          (axi_reading && rfdc_rvalid)) state <= ACK;
            ACK: state <= IDLE;
        endcase                          
    end    

    wire [RFDC_BITS*NSAMP-1:0] adc_vec[NCHAN-1:0];
    wire [NBITS-1:0] dbg_vec[NCHAN-1:0][NSAMP-1];
        
    generate
        genvar ch,smp;
        if (DEBUG == "TRUE") begin : ILA
            raw_ila u_ila(.clk(aclk),
                          .probe0(dbg_vec[0][0]),
                          .probe1(dbg_vec[0][1]),
                          .probe2(dbg_vec[0][2]),
                          .probe3(dbg_vec[0][3]),
                          .probe4(dbg_vec[0][4]),
                          .probe5(dbg_vec[0][5]),
                          .probe6(dbg_vec[0][6]),
                          .probe7(dbg_vec[0][7]));
        end
        // yoink the valid bits
        for (ch=0;ch<NCHAN;ch=ch+1) begin : MCH
            for (smp=0;smp<NSAMP;smp=smp+1) begin : MSMP 
                assign dbg_vec[ch][smp] =
                    adc_vec[ch][RFDC_BITS*smp + (RFDC_BITS-NBITS) +: NBITS];
                assign adc_dout[NBITS*NSAMP*ch+NBITS*smp +: NBITS] =
                    adc_vec[ch][RFDC_BITS*smp + (RFDC_BITS-NBITS) +: NBITS];
            end
        end
        if (DEVICE == "GEN1") begin : G1
            // gen1 needs to hook up all the clocks
            rfdc_gen1 
                u_gen1( .s_axi_aclk(wb_clk_i),
                        // need to handle resets in the bridge too!!
                        .s_axi_aresetn(!wb_rst_i),
                        `CONNECT_AXI4L_IF(s_axi_ , rfdc_ ),
                        // clock hookup
                        .adc0_clk_p(adc_clk_p[0]),
                        .adc0_clk_n(adc_clk_n[0]),
                        .adc1_clk_p(adc_clk_p[1]),
                        .adc1_clk_n(adc_clk_n[1]),
                        .adc2_clk_p(adc_clk_p[2]),
                        .adc2_clk_n(adc_clk_n[2]),
                        .adc3_clk_p(adc_clk_p[3]),
                        .adc3_clk_n(adc_clk_n[3]),
                        .dac0_clk_p(dac_clk_p),
                        .dac0_clk_n(dac_clk_n),
                        // adc hookup
                        .vin0_01_p(adc_in_p[0]),
                        .vin0_01_n(adc_in_n[0]),
                        .vin0_23_p(adc_in_p[1]),
                        .vin0_23_n(adc_in_n[1]),
                        .vin1_01_p(adc_in_p[2]),
                        .vin1_01_n(adc_in_n[2]),
                        .vin1_23_p(adc_in_p[3]),
                        .vin1_23_n(adc_in_n[3]),
                        .vin2_01_p(adc_in_p[4]),
                        .vin2_01_n(adc_in_n[4]),
                        .vin2_23_p(adc_in_p[5]),
                        .vin2_23_n(adc_in_n[5]),
                        .vin3_01_p(adc_in_p[6]),
                        .vin3_01_n(adc_in_n[6]),
                        .vin3_23_p(adc_in_p[7]),
                        .vin3_23_n(adc_in_n[7]),
                        // dacs, whatevs
                        .vout00_p(dac_out_p),
                        .vout00_n(dac_out_n),
                        // sysrefs
                        .sysref_in_p(sysref_p),
                        .sysref_in_n(sysref_n),
                        .user_sysref_adc(sysref_pl_i),
                        .user_sysref_dac(sysref_dac_i),
                        // interface clocks
                        .m0_axis_aresetn(1'b1),
                        .m0_axis_aclk(aclk),
                        .m1_axis_aresetn(1'b1),
                        .m1_axis_aclk(aclk),
                        .m2_axis_aresetn(1'b1),
                        .m2_axis_aclk(aclk),
                        .m3_axis_aresetn(1'b1),
                        .m3_axis_aclk(aclk),
                        .s0_axis_aresetn(1'b1),
                        .s0_axis_aclk(aclk),
                        .m00_axis_tdata( adc_vec[0] ),
                        .m00_axis_tready(1'b1),
                        .m00_axis_tvalid(),
                        .m02_axis_tdata( adc_vec[1] ),
                        .m02_axis_tready(1'b1),
                        .m02_axis_tvalid(),
                        .m10_axis_tdata( adc_vec[2] ),
                        .m10_axis_tready(1'b1),
                        .m10_axis_tvalid(),
                        .m12_axis_tdata( adc_vec[3] ),
                        .m12_axis_tready(1'b1),
                        .m12_axis_tvalid(),
                        .m20_axis_tdata( adc_vec[4] ),
                        .m20_axis_tready(1'b1),
                        .m20_axis_tvalid(),
                        .m22_axis_tdata( adc_vec[5] ),
                        .m22_axis_tready(1'b1),
                        .m22_axis_tvalid(),
                        .m30_axis_tdata( adc_vec[6] ),
                        .m30_axis_tready(1'b1),
                        .m30_axis_tvalid(),
                        .m32_axis_tdata( adc_vec[7] ),
                        .m32_axis_tready(1'b1),
                        .m32_axis_tvalid(),
                        .s00_axis_tdata({128{1'b0}}));                                                             
        end else begin : G3
            // gen3 only hooks up two of the clocks:
            // adc1_clk_p/n
            // dac0_clk_p/n
            rfdc_gen3 
                u_gen3( .s_axi_aclk(wb_clk_i),
                        // need to handle resets in the bridge too!!
                        .s_axi_aresetn(!wb_rst_i),
                        `CONNECT_AXI4L_IF(s_axi_ , rfdc_ ),
                        // clock hookup
                        .adc1_clk_p(adc_clk_p[1]),
                        .adc1_clk_n(adc_clk_n[1]),
                        .dac0_clk_p(dac_clk_p),
                        .dac0_clk_n(dac_clk_n),
                        // adc hookup
                        .vin0_01_p(adc_in_p[0]),
                        .vin0_01_n(adc_in_n[0]),
                        .vin0_23_p(adc_in_p[1]),
                        .vin0_23_n(adc_in_n[1]),
                        .vin1_01_p(adc_in_p[2]),
                        .vin1_01_n(adc_in_n[2]),
                        .vin1_23_p(adc_in_p[3]),
                        .vin1_23_n(adc_in_n[3]),
                        .vin2_01_p(adc_in_p[4]),
                        .vin2_01_n(adc_in_n[4]),
                        .vin2_23_p(adc_in_p[5]),
                        .vin2_23_n(adc_in_n[5]),
                        .vin3_01_p(adc_in_p[6]),
                        .vin3_01_n(adc_in_n[6]),
                        .vin3_23_p(adc_in_p[7]),
                        .vin3_23_n(adc_in_n[7]),
                        // dacs, whatevs
                        .vout00_p(dac_out_p),
                        .vout00_n(dac_out_n),
                        // sysrefs
                        .sysref_in_p(sysref_p),
                        .sysref_in_n(sysref_n),
                        .user_sysref_adc(sysref_pl_i),
                        .user_sysref_dac(sysref_dac_i),
                        // interface clocks
                        .m0_axis_aresetn(1'b1),
                        .m0_axis_aclk(aclk),
                        .m1_axis_aresetn(1'b1),
                        .m1_axis_aclk(aclk),
                        .m2_axis_aresetn(1'b1),
                        .m2_axis_aclk(aclk),
                        .m3_axis_aresetn(1'b1),
                        .m3_axis_aclk(aclk),
                        .s0_axis_aresetn(1'b1),
                        .s0_axis_aclk(aclk),
                        .m00_axis_tdata( adc_vec[0] ),
                        .m00_axis_tready(1'b1),
                        .m00_axis_tvalid(),
                        .m02_axis_tdata( adc_vec[1] ),
                        .m02_axis_tready(1'b1),
                        .m02_axis_tvalid(),
                        .m10_axis_tdata( adc_vec[2] ),
                        .m10_axis_tready(1'b1),
                        .m10_axis_tvalid(),
                        .m12_axis_tdata( adc_vec[3] ),
                        .m12_axis_tready(1'b1),
                        .m12_axis_tvalid(),
                        .m20_axis_tdata( adc_vec[4] ),
                        .m20_axis_tready(1'b1),
                        .m20_axis_tvalid(),
                        .m22_axis_tdata( adc_vec[5] ),
                        .m22_axis_tready(1'b1),
                        .m22_axis_tvalid(),
                        .m30_axis_tdata( adc_vec[6] ),
                        .m30_axis_tready(1'b1),
                        .m30_axis_tvalid(),
                        .m32_axis_tdata( adc_vec[7] ),
                        .m32_axis_tready(1'b1),
                        .m32_axis_tvalid(),
                        .s00_axis_tdata({128{1'b0}}));                                                             
        end
    endgenerate
endmodule
