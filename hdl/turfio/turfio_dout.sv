`timescale 1ns / 1ps
// turfio_dout does NOT need to be synchronous.
// Our training pattern is significantly simpler since
// we're only 8 bits. Let's look at possible pattern rotations:
// 0x6A (0110 1010)
//      (0011 0101) = 35
//      (1001 1010) = 9A
//      (0100 1101) = 4B
//      (1010 0110) = A6
// So this works fine.
//
// Event data is pretty big: from each SURF we send
// 1024 * 12 * 8 = 98304 bits = 12,288 bytes plus some header
// info. COBS encodes that with a maximum of ~49 extra bytes,
// or an overhead of around 0.4%.
//
// I *THINK* what I'm going to do to keep the register stuff
// responsive is just abscond with TXCLK and use it to send
// register responses. In the end this will just result in
// duplicating turfio_dout.
//
// NOTE NOTE NOTE: the input data SHOULD NOT ASSERT
// TVALID until it's got enough data to supply the entire
// frame CONSTANTLY. This isn't going to a problem for
// the data readout, and for the register responses
// the whole thing should be bufferable I think? dunno.
module turfio_dout(
        input       ifclk_i,
        input       ifclk_x2_i,
        input       ifclk_sync_i,
        
        input       train_i,
        
        input [7:0] s_axis_tdata,
        input       s_axis_tvalid,
        output      s_axis_tready,
        
        output      DOUT_P,
        output      DOUT_N                
    );
    
    parameter [7:0] TRAIN_VALUE = 8'h6A; 
    parameter INV_DOUT = 1'b0;
    parameter IFCLKTYPE = "IFCLK";
    // for us sync is easy, it just defines our toggle.
    // sync = 1 indicates the first phase in the full 16-clock
    // cycle. so if we buffer it, and use that to reset the toggle,
    // it puts us aligned.    
    reg sync_buf = 0;
    // tx_phase 
    reg tx_phase = 0;    
    // reregistered
    reg tx_phase_rereg = 0;
    // buffered
    reg tx_phase_buf = 0;
    // tx phase in ifclk
    reg tx_phase_ifclkx2 = 0;
    // we're not going to use OSERDESes because it bitches at us
    reg [7:0] tx_data = {8{1'b0}};
    reg [3:0] tx_data_ifclkx2 = {4{1'b0}};
        
    (* CUSTOM_CC_DST = IFCLKTYPE *)        
    reg training = 0;        
        
    always @(posedge ifclk_x2_i) begin
        tx_phase_ifclkx2 <= tx_phase_buf;
        // our sequence is now (from startup)
        // clk  tx_phase_buf    tx_phase_ifclkx2    descrip
        // 0    0               0
        // 1    0               0
        // 2    1               0                   tx_data[4:0] is valid
        // 3    1               1                   
        // 4    0               1                   tx_data[4:0] is valid
        // 5    0               0
        // 6    1               0
        // let's just try this for now
        // tx_phase_buf ^ tx_phase_ifclkx2 is high in phase 0 and phase 1
        // (and not in phase 0.5 and 1.5)
        if (tx_phase_buf ^ tx_phase_ifclkx2) begin
            tx_data_ifclkx2 <= tx_data[3:0];
        end else begin
            // we always shift DOWN
            tx_data_ifclkx2[1:0] <= tx_data_ifclkx2[3:2];
        end
    end        

    // we want our output data to BEGIN at the start phase
    // ifclk_sync_i is high in phase 0
    // sync_buf is high in phase 1
    // tx_phase is high in phase 0
    // tx_phase_rereg is high in phase 1
    // tx_phase_buf is high in phase 0
    // tx_phase_ifclk_x2 is high in phase 0.5
    //
    // so train[3:0] is on tx_data in phase 0
    // it is in tx_data_ifclkx2 on phase 0.5
    // it is therefore output on phase 1 and 1.5
    //
    // Need to see how reliable this is, it probably
    // will end up still being aligned but regardless
    // the entire point is that if I do a sync properly
    // I SHOULD NOT have to nybble-slip once I figure
    // out the alignment. Yet another way of confirming
    // alignment. 
    always @(posedge ifclk_i) begin        
        sync_buf <= ifclk_sync_i;
        training <= train_i;
    
        if (sync_buf) tx_phase <= 1'b1;
        else tx_phase <= ~tx_phase;

        tx_phase_rereg <= tx_phase;
        tx_phase_buf <= tx_phase_rereg;

        // we capture on tx_phase low, since that
        // occurs in clocks 1/3/5/7/9/11/13/15
        if (!tx_phase) begin
            if (training) tx_data <= TRAIN_VALUE;
            else if (s_axis_tvalid) tx_data <= s_axis_tdata;
            else tx_data <= {8{1'b0}};
        end else begin
            // we always shift DOWN
            tx_data[3:0] <= tx_data[7:4];
        end
    end
    
    assign s_axis_tready = !tx_phase && !training;
    
    wire oddre2_out;
    ODDRE1 #(.SRVAL(INV_DOUT)) u_dout_ddr(.C(ifclk_x2_i),
                                          .D1(tx_data_ifclkx2[0] ^ INV_DOUT),
                                          .D2(tx_data_ifclkx2[1] ^ INV_DOUT),
                                          .SR(1'b0),
                                          .Q(oddre2_out));
    
    obufds_autoinv #(.INV(INV_DOUT)) u_dout(.I(oddre2_out),.O_P(DOUT_P),.O_N(DOUT_N));    
    
endmodule
