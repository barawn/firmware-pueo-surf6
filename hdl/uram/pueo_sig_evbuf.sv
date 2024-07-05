`timescale 1ns / 1ps
// Wrapper for the SIGBUF and EVBUF components.
// Also handles reset sequencing and buffering of
// trigger requests.
module pueo_sig_evbuf #(parameter NCHAN = 8,
                        parameter NSAMP = 8,
                        parameter NBIT = 12,
                        parameter TRIGBIT = 15)(
        // data clock
        input aclk_i,
        // indicates first clock of 3 of common 125 MHz period
        input aclk_sync_i,
        // memory clock
        input memclk_i,
        // indicates first clock of 4 of common 125 MHz period
        input memclk_sync_i,
        
        // start sigbuf running. This occurs synchronously using the SYNC bitcommand
        // when it's enabled via a register.
        input sigbuf_start_i,
        // stop sigbuf. This is just generated via a register and doesn't actually 
        // stop the *writing* to sigbuf, but resets the readout and evbuf.
        // This can be done multiple times!
        input sigbuf_stop_i,
        
        // data output from RFdc
        input [NCHAN*NSAMP*NBIT-1:0] dat_i,

        // trigger time input from the command decoder
        input [TRIGBIT-1:0] trig_time_i,
        input               trig_valid_i 
    );
endmodule
