`timescale 1ns / 1ps
// this is very similar to the turf_cin_parallel_sync
// except we have a clock enable (cin_valid_i) and
// we also have the bitslip module in front b/c
// we need to use our own bitslip.
module turfio_cin_parallel_sync(
        input aclk_i,
        // data in aclk domain
        input [3:0] cin_i,
        // data valid
        input cin_valid_i,
        // bitslip request
        input bitslip_i,
        // reset the bitslip module
        input bitslip_rst_i,
        // request a capture even though unaligned
        input capture_i,
        // reset lock
        input lock_rst_i,
        // lock onto the next correct sequence and keep going
        input lock_i,
        // sequence found, lock is OK
        output locked_o,
        // out of training. This JUST needs to go to a register, that's it.
        output running_o,
        // output (after capture or lock)
        output [31:0] cin_parallel_o,
        output        cin_parallel_valid_o,
        output cin_biterr_o
    );
    
    parameter [31:0] TRAIN_SEQUENCE = 32'hA55A6996;
    parameter CLKTYPE = "SYSREFCLK";
    parameter DEBUG = "TRUE";
    
    wire [3:0] cin_post_bitslip;
    wire       cpb_valid;
    // this is actually just cin_valid_i but whatever
    wire       cpb_will_be_valid;
    bit_align u_bitslip(.din(cin_i), .ce_din(cin_valid_i),
                        .dout(cin_post_bitslip),
                        .ce_dout(cpb_valid),
                        .prece_dout(cpb_will_be_valid),
                        .slip(bitslip_i),
                        .rst(bitslip_rst_i),
                        .clk(aclk_i));

    reg [27:0] cin_history = {28{1'b0}};
    wire [31:0] current_cin = { cin_post_bitslip, cin_history };
    (* CUSTOM_CC_SRC = CLKTYPE, CUSTOM_CC_DST = CLKTYPE *)
    reg [31:0] cin_capture = {32{1'b0}};
    reg enable_capture = 0;
    reg enable_lock = 0;
    (* CUSTOM_CC_SRC = CLKTYPE *)
    reg locked = 0;
    // running indicates we've seen something OTHER than train data after locking.
    (* CUSTOM_CC_SRC = CLKTYPE *)
    reg running = 0;
    // this was dropped in the TURFIO b/c locked is actually what you want
//    reg locked_rereg = 0;
    reg [3:0] aclk_sequence = {4{1'b0}};
    // BIT ERROR TESTING
    wire [3:0] cin_delayed;
    // Bit error generation. We use the bottom bits of cin_history to reduce
    // loading, since they feed nothing except the capture register. Now
    // of course they've got an extra load, but whatever. We mainly wanted
    // to get away from the input registers since they're special.
    // It's just a delay so we can use an SRL with address set to 7 for it.
    reg cin_biterr = 0;
    assign     cin_biterr_o = cin_biterr;
    srlvec #(.NBITS(4)) u_cin_srl(.clk(aclk_i),
                                  .ce(cpb_valid),
                                  .a(4'h7),
                                  .din(cin_history[3:0]),
                                  .dout(cin_delayed));        

    wire cin_train_match = (current_cin == TRAIN_SEQUENCE);
    always @(posedge aclk_i) begin
        if (lock_rst_i) enable_lock <= 1'b0;
        else if (lock_i) enable_lock <= 1'b1;
        
        // update the history just before cpb_valid goes
        // this means that {cin_post_bitslip, cin_history} is always valid
        if (cpb_will_be_valid) begin
            cin_history[24 +: 4] <= cin_post_bitslip;
            cin_history[20 +: 4] <= cin_history[24 +: 4];
            cin_history[16 +: 4] <= cin_history[20 +: 4];
            cin_history[12 +: 4] <= cin_history[16 +: 4];
            cin_history[8 +: 4] <= cin_history[12 +: 4];
            cin_history[4 +: 4] <= cin_history[8 +: 4];
            cin_history[0 +: 4] <= cin_history[4 +: 4];            
        end
        
        // this might be big at 375 MHz, maybe pipeline it
        if (lock_rst_i) locked <= 1'b0;
        else begin
            if (enable_lock && cpb_valid && cin_train_match) locked <= 1'b1;
        end
        
        // we want to keep this as the same comparator, so we can't
        // use the output command which is reregistered. 
        if (lock_rst_i) running <= 1'b0;
        else begin
            if (locked && enable_capture && cpb_valid && current_cin != TRAIN_SEQUENCE) running <= 1'b1;
        end            
        
//        if (lock_rst_i) locked_rereg <= 1'b0;
//        else locked_rereg <= locked;
        
        if (!locked) aclk_sequence <= 4'h0;
        else begin
            if (cpb_valid) aclk_sequence <= aclk_sequence[2:0] + 1;
        end
        // you don't need the top bit here because you can't have 1110
        // because you go 0111 => 1000 => 0001
        // need to qualify here because we want enable_capture HIGH
        // in aclk_sequence 7
        if (cpb_valid) enable_capture <= aclk_sequence[2:0] == 3'h6;
        // just capture immediately if we're told to.
        // it doesn't matter if we're off-sequence, it's not like anything's
        // changing.
        if (capture_i || (cpb_valid && enable_capture)) cin_capture <= current_cin;
        
        // when we're locked, turn off biterrs because
        // it's no longer an 8-clock repeating pattern
        if (locked) cin_biterr <= 1'b0;
        else cin_biterr <= (cin_history[3:0] != cin_delayed[3:0]) && cpb_valid;
    end
    
    generate
        if (DEBUG == "TRUE") begin : ILA
            (* CUSTOM_CC_DST = CLKTYPE *)
            reg cin_was_captured = 0;
            always @(posedge aclk_i) begin : DBG_CAP
                cin_was_captured <= (capture_i || (cpb_valid && enable_capture));
            end 
            turfio_cin_ila u_ila(.clk(aclk_i),
                                 .probe0(enable_lock),
                                 .probe1(locked),
                                 .probe2(cin_history[24 +: 4]),
                                 .probe3(cin_was_captured),
                                 .probe4(cin_parallel_o),
                                 .probe5(cin_parallel_valid_o),
                                 .probe6(cin_biterr),
                                 .probe7(current_cin),
                                 .probe8(aclk_sequence),
                                 .probe9(cpb_valid));
        end
    endgenerate    
    assign cin_parallel_valid_o = aclk_sequence[3] && cpb_valid;
    assign cin_parallel_o = cin_capture;
    assign locked_o = locked;
    assign running_o = running;
    assign cin_biterr_o = cin_biterr;
endmodule
