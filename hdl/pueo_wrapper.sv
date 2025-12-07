`timescale 1ns / 1ps
`include "interfaces.vh"
// addrlen here defines the max lookback time.
// The total URAM usage is 
// NCHAN*2^(ADDRLEN-12)
// There are 80 total in the ZU47 and
// 48 in the ZU25, and each adds 
// 8 us of buffering.

// DUMB ATTEMPT TO GET THINGS WORKING
module pueo_wrapper #(parameter NBITS=12,
                      parameter NSAMP=8,
                      parameter NCHAN=8,
                      parameter MEMCLKTYPE = "NONE",
                      parameter IFCLKTYPE = "NONE")(
        // aclk_sync_i are memclk_sync_i come from the sync gen
        // NOT from the command processor. These are not do_sync!
        input aclk_i,
        input aclk_sync_i,      // phase 0 of the 3-cycle phase
        input memclk_i,
        input memclk_sync_i,    // phase 0 of the 4-cycle phase

        // the phasing up of ifclk so that it outputs data correctly
        // is done by the axi4-stream link below
        input ifclk_i,
        // these commands are multicycle constraints from aclk!
        input run_rst_i,
        input run_stop_i,
        
        input [NBITS*NSAMP*NCHAN-1:0] ch_dat_i,
        
        // TRIGGER RELATED CONTROLS HERE
        // aclk domain
        input [15:0] trig_time_i,
        input        trig_time_valid_i,
    
        // dout path
        output [7:0] dout_data_o,
        output       dout_data_valid_o,
        input        dout_data_phase_i,
                
        // this is the bullshit stream program interface
        // from idctrl
        input [23:0] rdholdoff_i,
        // from idctrl
        input       fw_loading_i,
        // this is in aclk domain 
        input [7:0] fw_tdata,
        // don't f$!(ing write if you're actually running
        input       fw_tvalid,
        // this is set to 1, hilariously
        output      fw_tready,
        // mark input
        input [1:0] fw_mark_i,
        // indicates when writes happen in banks
        output [1:0] fwmon_wr_o
    );
    
    localparam MEMSAMP = NSAMP*3/4;
    
    wire [NBITS*NSAMP*NCHAN-1:0] data_vec;
    wire [NBITS*MEMSAMP*NCHAN-1:0] dout_vec;
    wire [NCHAN-1:0] dout_valid;

    assign data_vec = ch_dat_i;    

    // We previously had trigger holdoffs of 65535*8 ns = 524,280 ns
    // Our event size is 98,336 bits. At 500 Mbit/s this is
    // 196,672 ns. This means a nominally equivalent read holdoff is
    // roughly 20475. This ignores the trigger transmission time because
    // that would have been pipelined through anyway. 
    // THIS IS CAPTURED AT RUN START
    (* CUSTOM_CC_DST = IFCLKTYPE *)
    reg [23:0] current_rdholdoff = 24'd20475;
    (* CUSTOM_MC_DST_TAG = "RUNRST" *)
    reg run_rst_ifclk = 0;
    always @(posedge ifclk_i) begin
        run_rst_ifclk <= run_rst_i;
        if (run_rst_ifclk) current_rdholdoff <= rdholdoff_i;
    end
    
    // RESETS
    // comes from pueo_uram_v4 when not running.
    wire event_reset_memclk;
    wire event_reset_aclk;
    
    // this has to hold longer b/c of the FIFO reset time for async
    // this does NOT need a multicycle tag.
    reg addrfifo_resetb = 1;
    wire addrfifo_resetb_delayed;
    SRLC32E u_addrreset(.D(addrfifo_resetb),.CE(1'b1),.CLK(aclk_i),.Q31(addrfifo_resetb_delayed));
    always @(posedge aclk_i) begin
        if (run_stop_i) addrfifo_resetb <= 1'b0;
        else if (!addrfifo_resetb_delayed) addrfifo_resetb <= 1'b1;
    end        

    // signal from SIGBUF to EVBUF
    wire begin_readout;
    
    // fake AXI4-Stream
    `DEFINE_AXI4S_MIN_IF( addrin_ , 16 );
    assign addrin_tdata = { 1'b0, trig_time_i };
    assign addrin_tvalid = trig_time_valid_i;
    // out of the clock-cross fifo
    `DEFINE_AXI4S_MIN_IF( addr_ , 16 );
    // NOTE: USING A FIFO LIKE THIS SUCKS!!
    // FIX THIS LATER - WE SHOULDN'T NEED ONE AT ALL!!    
    addr_fifo u_addrfifo(.s_axis_aclk( aclk_i ),
                         .m_axis_aclk( memclk_i ),
                         .s_axis_aresetn( addrfifo_resetb ),
                         `CONNECT_AXI4S_MIN_IF( s_axis_ , addrin_ ),
                         `CONNECT_AXI4S_MIN_IF( m_axis_ , addr_ ));
                         
    reg [15:0] trig_num = {16{1'b0}};
    always @(posedge aclk_i) begin
        if (run_rst_i) trig_num <= {16{1'b0}};
        else if (trig_time_valid_i) trig_num <= trig_num + 1;
    end

    pueo_uram_v4 #(.SCRAMBLE_OPT("TRUE"))
        uut(.aclk(aclk_i),            
            .aclk_sync_i(aclk_sync_i),
            .memclk(memclk_i),
            .memclk_sync_i(memclk_sync_i),
            .run_rst_i(run_rst_i),
            .run_stop_i(run_stop_i),
            .event_rst_o(event_reset_memclk),
            .event_rst_aclk_o(event_reset_aclk),
            .dat_i(data_vec),
            .begin_o(begin_readout),
            .dat_o(dout_vec),
            .dat_valid_o(dout_valid),
            .s_axis_tdata(addr_tdata),
            .s_axis_tvalid(addr_tvalid),
            .s_axis_tready(addr_tready));   
    wire [1:0] mark_ifclk;
    flag_sync u_mark0(.in_clkA(fw_mark_i[0]),.out_clkB(mark_ifclk[0]),
                      .clkA(aclk_i),.clkB(ifclk_i));
    flag_sync u_mark1(.in_clkA(fw_mark_i[1]),.out_clkB(mark_ifclk[1]),
                      .clkA(aclk_i),.clkB(ifclk_i));                      
    // OH DEAR GOD THIS IS AWKWARD!!
    uram_event_buffer_v3 #(.DEBUG("FALSE"),
                           .MEMCLKTYPE(MEMCLKTYPE),
                           .IFCLKTYPE(IFCLKTYPE))
                      u_evbuf( .memclk_i(memclk_i),
                               .memclk_rst_i(event_reset_memclk),
                               .aclk_i(aclk_i),
                               .aclk_rst_i(event_reset_aclk),
                               .ifclk_i(ifclk_i),
                               .ifclk_rst_i(),
                               .begin_i(begin_readout),
                               .dat_i(dout_vec),
                               .dat_valid_i(dout_valid),
                               .trig_time_i(trig_time_i),
                               .event_no_i(trig_num),
                               .trig_valid_i(trig_time_valid_i),
                               .rdholdoff_i(current_rdholdoff),
                               .dout_data_o(dout_data_o),
                               .dout_data_valid_o(dout_data_valid_o),
                               .dout_data_phase_i(dout_data_phase_i),
                               // skip dout_data_last_o right now
                               .fw_dat_i(fw_tdata),
                               .fw_load_i(fw_loading_i),
                               .fw_wr_i(fw_tvalid),
                               .fw_mark_i(mark_ifclk),
                               .fwmon_wr_o(fwmon_wr_o) 
                               );
        
    assign fw_tready = 1'b1;    
        

endmodule
