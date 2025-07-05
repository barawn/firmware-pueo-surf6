`timescale 1ns / 1ps
`include "interfaces.vh"
// turfio_cout is synchronous.
// our training pattern is still 
//     parameter [31:0] TRAIN_SEQUENCE = 32'hA55A6996;
// we need to screw around to figure out how syncing works later,
// but as an absolute first attempt this will work.
//
// note that we stay in reset (all 1s) until the startup
// sequence completes, at which point we fall back to
// the training sequence.
module turfio_cout(
        input       ifclk_i,
        input       ifclk_x2_i,
        input       ifclk_sync_i,
        
        input       train_i,

        // make this properly an AXI4-stream
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( cout_ , 32),

        output      COUT_P,
        output      COUT_N                
    );
    // COUT starts off high, then flops back to the training
    // pattern once we're out of the startup sequence.
    // This is different than DOUT, which allows us to detect
    // the startup state of each SURF with a bit more granularity.
    parameter INITIAL_COUT = 1'b1;
    parameter [31:0] TRAIN_VALUE = 32'hA55A6996;
    parameter INV_COUT = 1'b0;
    parameter IFCLKTYPE = "IFCLK";

    localparam [2:0] COMMAND_PHASE_RESET_VAL = 3'd1;

    // this is the cross-clock from the register
    (* CUSTOM_CC_DST = IFCLKTYPE *)        
    reg training = 0;        
    // this is reregistered to allow for rising edge detection to clear
    // ifclk_not_running.
    reg [1:0] training_begin = {2{1'b0}};
    
    // dude what the hell was I doing this should be all zeros dumbass
    wire [31:0] cur_cout_value = (cout_tvalid) ? cout_tdata : 32'h00000000;
    wire [31:0] value_to_send = (training) ? TRAIN_VALUE : cur_cout_value;

    reg [2:0] command_phase = {3{1'b0}};

    reg cout_ready_reg = 0;
    
    reg [31:0] command_hold = {32{1'b0}};
    
    reg [3:0] tx_data_ifclkx2 = {4{1'b0}};    

    reg ifclk_not_running = 1;

    // we have two phases here: first, in ifclk,
    // we're periodically grabbing 4 new bits to pass
    // over to ifclk_x2_i.
    // next, in ifclk_x2_i, we're toggling between
    // capturing the bits and shifting them down.
    //
    // this looks a ton like the dout, except here
    // we have an 8-stage phase as well. so long
    // as they're reset the same, it'll be fine.
    
    reg sync_buf = 0;
    reg tx_phase_buf = 0;
    reg tx_phase = 0;
    reg tx_phase_rereg = 0;
    reg tx_phase_ifclkx2 = 0;
        
    // this part is EXACTLY the same as DOUT
    always @(posedge ifclk_x2_i) begin
        tx_phase_ifclkx2 <= tx_phase_buf;
        // our sequence is now (from startup)
        // clk  tx_phase_buf    tx_phase_ifclkx2    descrip
        // 0    0               0
        // 1    0               0
        // 2    1               0                   tx_data[3:0] is valid
        // 3    1               1                   
        // 4    0               1                   tx_data[3:0] is valid
        // 5    0               0
        // 6    1               0
        // let's just try this for now
        // tx_phase_buf ^ tx_phase_ifclkx2 is high in phase 0 and phase 1
        // (and not in phase 0.5 and 1.5)
        if (tx_phase_buf ^ tx_phase_ifclkx2) begin
            tx_data_ifclkx2 <= command_hold[3:0];
        end else begin
            // we always shift DOWN
            tx_data_ifclkx2[1:0] <= tx_data_ifclkx2[3:2];
        end
    end        


    always @(posedge ifclk_i) begin        
        // detect the *first* time we enter training.
        // we need to do it this way because ifclk's going to go
        // wackity-wacko during alignment and everything Will Be Weird.
        // All our states can go crazy during clock alignment and
        // such, but training begin acts to start stuff.
        if (!training_begin[1] && training_begin[0])
            ifclk_not_running <= 1'b0;
        
        sync_buf <= ifclk_sync_i;
        training <= train_i;
        training_begin <= {training_begin[0], training};
                    
        if (sync_buf) tx_phase <= 1'b1;
        else tx_phase <= ~tx_phase;

        // this is parameterizable to allow us to adjust things.
        // once we issue a sync we should NEVER EVER need to
        // do anything, the alignment should be spot-on fixed.
        if (sync_buf) command_phase <= COMMAND_PHASE_RESET_VAL;
        else command_phase <= command_phase + 1;

        tx_phase_rereg <= tx_phase;
        tx_phase_buf <= tx_phase_rereg;

        // we capture on command_phase = 7
        // always shift down
        if (command_phase == 7) command_hold <= value_to_send;
        else begin
            // we don't care about the shift in, so just leave it alone,
            // it'll get reset.
            command_hold[27:0] <= command_hold[31:4];
        end
        
        // tready goes high in 7
        cout_ready_reg <= command_phase == 6;
    end
    
    wire oddre2_out;
    ODDRE1 #(.SRVAL(1 ^ INV_COUT)) u_cout_ddr(.C(ifclk_x2_i),
                                          .D1(tx_data_ifclkx2[0] ^ INV_COUT),
                                          .D2(tx_data_ifclkx2[1] ^ INV_COUT),
                                          .SR(ifclk_not_running),
                                          .Q(oddre2_out));
    obuftds_autoinv #(.INV(INV_COUT)) u_cout(.I(oddre2_out),.T(1'b0),.O_P(COUT_P),.O_N(COUT_N));    
        
    assign cout_tready = cout_ready_reg;
endmodule
