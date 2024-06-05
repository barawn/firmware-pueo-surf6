`timescale 1ns / 1ps
`include "interfaces.vh"
// addrlen here defines the max lookback time.
// The total URAM usage is 
// NCHAN*2^(ADDRLEN-12)
// There are 80 total in the ZU47 and
// 48 in the ZU25, and each adds 
// 8 us of buffering.
module pueo_wrapper #(parameter NBITS=12,
                      parameter NSAMP=8,
                      parameter NCHAN=8,
                      parameter RDLEN=1024,
                      parameter ADDRLEN=14,
                      parameter TRIGBITS=15)(
        input aclk_i,
        input aclk_phase_i,
        input aclk_sync_i,
        input memclk_i,
        input memclk_phase_i,
        input memclk_sync_i,
        input ifclk_i,
        input ifclk_x2_i,
        input ifclk_x2_phase_i,

        input [NBITS*NSAMP-1:0] chA_i,
        input [NBITS*NSAMP-1:0] chB_i,
        input [NBITS*NSAMP-1:0] chC_i,
        input [NBITS*NSAMP-1:0] chD_i,
        input [NBITS*NSAMP-1:0] chE_i,
        input [NBITS*NSAMP-1:0] chF_i,
        input [NBITS*NSAMP-1:0] chG_i,
        input [NBITS*NSAMP-1:0] chH_i,
        
        // TRIGGER RELATED CONTROLS HERE
        // aclk domain
        input [TRIGBITS-1:0] trig_time_i,
        input                trig_time_valid_i,
        // ifclk domain
        output [7:0]        m_data_tdata,
        output              m_data_tvalid,
        input               m_data_tready        
    );
    
    `DEFINE_AXI4S_MIN_IFV( dmclk_ , 72, 8);
    
    // Our event buffer uses cascaded block RAMs
    // to merge the channels. Each channel gets
    // 2 block RAMs, giving a total buffer size of
    // 8 events (72 x 
    generate
        genvar i;
        for (i=0;i<NCHAN;i=i+1) begin : CHBUF
            
        end
    endgenerate    
endmodule
