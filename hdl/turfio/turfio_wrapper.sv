`timescale 1ns / 1ps
`include "interfaces.vh"
// based off the methods used on the TURF and TURFIO.
// WHAT WE NEED TO STEAL FROM THE TURFIO:
// We need to handle the RXCLK->IFCLK transition the same way to ensure
// that sysclk is propagating synchronized.
module turfio_wrapper #(parameter INV_CIN = 1'b0,
                        parameter INV_COUT = 1'b0,
                        parameter INV_RXCLK = 1'b0,
                        parameter INV_TXCLK = 1'b0,
                        parameter INV_DOUT = 1'b0)(
        input wb_clk_i,
        input wb_rst_i,
        `TARGET_NAMED_PORTS_WB_IF(wb_ , 11, 32),

        input aclk_i,
        input aclk_ok_i,
        // The turfio wrapper handles the memclk/ifclk PLL
        // as well, since it needs to get ifclk phased up
        // to rxclk.
        input aclk_locked_i,
        output aclk_reset_o,
        output clk300_o,
        
        // oh this is such a pain
        input ifclk_i,
        input ifclk_x2_i,
        input memclk_i,
        
        output aclk_sync_o,
        output memclk_sync_o,        

        output rxclk_o,
        input rxclk_ok_i,

        output [31:0] command_o,
        output command_valid_o,
        input [31:0] response_i,
        input response_valid_i,

        input RXCLK_P,
        input RXCLK_N,
        output TXCLK_P,
        output TXCLK_N,
        input CIN_P,
        input CIN_N,
        output COUT_P,
        output COUT_N,
        output DOUT_P,
        output DOUT_N               
    );

    // let's test things
    reg aclk_toggle = 0;
    always @(posedge aclk_i) aclk_toggle <= ~aclk_toggle;
    reg ifclk_capture = 0;
    reg ifclk_out = 0;
    always @(posedge ifclk_i) begin
        ifclk_capture <= aclk_toggle;
        ifclk_out <= ifclk_capture;
    end
    // what-freaking-ever
    obufds_autoinv #(.INV(INV_TXCLK)) u_txclk(.I(1'b0),.O_P(TXCLK_P),.O_N(TXCLK_N));
    obufds_autoinv #(.INV(INV_COUT)) u_cout(.I(1'b0),.O_P(COUT_P),.O_N(COUT_N));
    obufds_autoinv #(.INV(INV_DOUT)) u_dout(.I(ifclk_out),.O_P(DOUT_P),.O_N(DOUT_N));    


    // Register core outputs
    wire ps_en;
    wire ps_done;
    wire mmcm_locked;
    wire mmcm_rst;
    wire capture_err;
    wire align_err;
    
    wire cin_rst;
    wire en_vtc;
    wire delay_load;
    wire delay_rd;
    wire [1:0] delay_sel;
    wire [8:0] delay_cntvaluein;
    wire [8:0] delay_cntvalueout;

    wire idelayctrl_rdy;
    wire idelayctrl_rst;
    
    wire cin_err;
    wire capture_req;
    wire bitslip_rst;
    wire bitslip;
    
    wire lock_rst;
    wire lock_req;
    wire lock_status;
    
    wire [1:0] train_en;

    turfio_register_core #(.CAPTURE_DATA_WIDTH(32))
        u_registers(.wb_clk_i(wb_clk_i),
                    .wb_rst_i(wb_rst_i),
                    `CONNECT_WBS_IFS(wb_ , wb_ ),
                    .rxclk_i(rxclk_o),
                    .rxclk_ok_i(rxclk_ok_i),
                    .aclk_i(aclk_i),
                    .aclk_ok_i(aclk_ok_i),
                    .aclk_locked_i(aclk_locked_i),
                    .aclk_reset_o(aclk_reset_o),
                    .ifclk_alignerr_i(align_err),
                    
                    .ps_en_o(ps_en),
                    .ps_done_i(ps_done),
                    .mmcm_locked_i(mmcm_locked),
                    .mmcm_rst_o(mmcm_rst),
                    .capture_err_i(capture_err),
                    .cin_rst_o(cin_rst),
                    .en_vtc_o(en_vtc),
                    .delay_load_o(delay_load),
                    .delay_rd_o(delay_rd),
                    .delay_sel_o(delay_sel),
                    .delay_cntvaluein_o(delay_cntvaluein),
                    .delay_cntvalueout_i(delay_cntvalueout),
                    
                    .idelayctrl_rdy_i(idelayctrl_rdy),
                    .idelayctrl_rst_o(idelayctrl_rst),
                    
                    .cin_err_i(cin_err),
                    .capture_req_o(capture_req),
                    .bitslip_rst_o(bitslip_rst),
                    .bitslip_o(bitslip),
                    
                    .lock_rst_o(lock_rst),
                    .lock_req_o(lock_req),
                    .lock_status_i(lock_status),
                    
                    .train_en_o(train_en),
                    .capture_data_i(command_o));
    
    (* IODELAY_GROUP = "RXCLK", CUSTOM_CC_SRC = "CLK300", CUSTOM_CC_DST = "CLK300" *)
    IDELAYCTRL #(.SIM_DEVICE("ULTRASCALE")) u_idelayctrl(.REFCLK(clk300_o),
                            .RST(idelayctrl_rst),
                            .RDY(idelayctrl_rdy));
    
    // rxclk is a clock path, we have to use the norm
    wire rxclk_norm;
    wire rxclk_compl;
    ibufds_autoinv #(.INV(INV_RXCLK))
        u_rxclk_ibufds(.I_P(RXCLK_P),.I_N(RXCLK_N),.O(rxclk_norm),.OB(rxclk_compl));
    // after MMCM
    wire rxclk;  
    assign rxclk_o = rxclk;
    // 2x RXCLK after MMCM
    wire rxclk_x2;
    // 3x RXCLK after MMCM for aclk transfer
    wire rxclk_x3;
    // RXCLK phase indicator in rxclk_x3
    wire rxclk_ce;
        
    turfio_rxclk_gen #(.INV_RXCLK(INV_RXCLK))
        u_rxclk(.rxclk_in(rxclk_norm),
                .rxclk_o(rxclk),
                .rxclk_x2_o(rxclk_x2),
                .rxclk_x3_o(rxclk_x3),
                .rxclk_ce_o(rxclk_ce),
                .clk300_o(clk300_o),
                .rst_i(mmcm_rst),
                .locked_o(mmcm_locked),
                .ps_clk_i(wb_clk_i),
                .ps_en_i(ps_en),
                .ps_done_o(ps_done));
                
    // now the CIN module looks more like the TURF side, because we don't
    // have a bitslip module. Except we integrate a bit more.
    wire [3:0] cin_rxclk;
    
    turfio_cin_surf #(.INV(INV_CIN),.CLKTYPE("RXCLK"))
        u_cin(.rxclk_i(rxclk),
              .rxclk_x2_i(rxclk_x2),
              .rst_i(cin_rst),
              .en_vtc_i(en_vtc),
              .delay_load_i(delay_load),
              .delay_rd_i(delay_rd),
              .delay_sel_i(delay_sel),
              .delay_cntvaluein_i(delay_cntvaluein),
              .delay_cntvalueout_o(delay_cntvalueout),
              .data_o(cin_rxclk),
              .CIN_P(CIN_P),
              .CIN_N(CIN_N));
    
    // the RXCLK->ACLK transfer is based on the rxclk->sysclk transfer
    // except first we transfer into rxclk_x3 and transfer *that* over
    wire [3:0] cin_aclk;
    wire ce_aclk;
    wire syncclk_toggle;
    // if this STILL has a problem, we'll probably use
    // aclk to generate asynchronous resets on the memclk/ifclk
    // sides or something. aclk is continuously running
    // even through the reset, so it can tell the others
    // when to cleanly start up.
    pueo_clk_phase_v2 u_aclk_track( .aclk(aclk_i),
                                 .memclk(memclk_i),
                                 .syncclk(ifclk_i),
                                 .locked_i(aclk_locked_i),
                                 .syncclk_toggle_o(syncclk_toggle),
                                 .memclk_sync_o(memclk_sync_o),
                                 .aclk_sync_o(aclk_sync_o));
    
    rxclk_aclk_transfer
        u_cin_transfer(.rxclk_i(rxclk),
                       .rxclk_x3_i(rxclk_x3),
                       .rxclk_ce_i(rxclk_ce),                       
                       .data_i(cin_rxclk),
                       .aclk_i(aclk_i),
                       .aclk_sync_i(aclk_sync_o),                   
                       .data_o(cin_aclk),
                       .data_ce_o(ce_aclk),
                       .align_err_o(align_err),
                       .syncclk_toggle_i(syncclk_toggle),
                       .capture_err_o(capture_err));

    turfio_cin_parallel_sync 
        u_parallelizer(.aclk_i(aclk_i),
                       .cin_i(cin_aclk),
                       .cin_valid_i(ce_aclk),
                       .bitslip_i(bitslip),
                       .bitslip_rst_i(bitslip_rst),
                       .capture_i(capture_req),
                       .lock_rst_i(lock_rst),
                       .lock_i(lock_req),
                       .locked_o(lock_status),
                       .cin_biterr_o(cin_err),
                       .cin_parallel_o(command_o),
                       .cin_parallel_valid_o(command_valid_o));

//                    .cin_err_i(cin_err),
//                    .capture_req_o(capture_req),
//                    .bitslip_rst_o(bitslip_rst),
//                    .bitslip_o(bitslip),
                    
//                    .lock_rst_o(lock_rst),
//                    .lock_req_o(lock_req),
//                    .lock_status_i(lock_status),
        
endmodule
