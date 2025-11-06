`timescale 1ns / 1ps
// Single-channel version of the sync transfer.
module uram_sync_transfer #(
        parameter NSAMP=8,
        parameter NBIT=12,
        parameter SCRAMBLE_OPT = "TRUE"
    )(
        input aclk_i,
        input aclk_sync_i,
        input memclk_i,
        input memclk_sync_i,
        input [NSAMP*NBIT-1:0] dat_i,
        output [(NSAMP*3/4)*NBIT-1:0] dat_o
    );

    // indicates what phase of the memclk we're in    
    (* MAX_FANOUT = 10 *)
    reg [1:0] write_phase = {2{1'b0}};
    // indicates what phase of the aclk we're in
    (* MAX_FANOUT = 10 *)
    reg [2:0] buffer_phase = {3{1'b0}};
    
    // These are the aclk-side buffers.
    // On the ACLK side, they're captured in 3 phases,
    // and on the MEMCLK side they're captured in 4.
    // That means they're actually each broken in half,
    // bufferA is split into bottom 2/top 6
    // bufferB is split into bottom 6/top 2
    // bufferC is split into bottom 4/top 4
    // then they get written
    // B bottom 6
    // B top 2 C bottom 4
    // C top 4 A bottom 2
    // A top 6    
    // We do it this way to make the constraint lookup
    // easier.
    // (we parameterize this to make it work for a 4 sample guy too)
    localparam NSAMP_A_TOP = (NSAMP*3/4);
    localparam NSAMP_A_BOT = (NSAMP*1/4);
    localparam NSAMP_B_TOP = (NSAMP*1/4);
    localparam NSAMP_B_BOT = (NSAMP*3/4);
    localparam NSAMP_C_TOP = (NSAMP*2/4);
    localparam NSAMP_C_BOT = (NSAMP*2/4);
    
    localparam NSAMP_MEM = (NSAMP*3/4);
    
    // CUSTOM_MC_SRC/DST is spec'd in SOURCE clocks and must tag on the SOURCE
    // first aclk buffer
    
    // atop: min -3*tick=-2 ns = -0.75, max 9*tick = 6 ns =2.25
    (* CUSTOM_MC_SRC_TAG = "ATOP_XFER", CUSTOM_MC_MIN = "-0.75", CUSTOM_MC_MAX = "2.25" *)
    reg [NBIT*(NSAMP_A_TOP)-1:0] bufferA_top = {NBIT*NSAMP_A_TOP{1'b0}};
    // abot: min -6*tick=4ns=1.5, max 6*tick = 4ns = 1.5
    (* CUSTOM_MC_SRC_TAG = "ABOT_XFER", CUSTOM_MC_MIN = "-1.5", CUSTOM_MC_MAX = "1.5" *)
    reg [NBIT*(NSAMP_A_BOT)-1:0] bufferA_bot = {NBIT*NSAMP_A_BOT{1'b0}};
    // btop -1, 11: min -0.6667 ns = -0.25, max 11=7.333=2.75
//    (* CUSTOM_MC_SRC_TAG = "BTOP_XFER", CUSTOM_MC_MIN = "-0.25", CUSTOM_MC_MAX = "2.75" *)
    (* CUSTOM_MC_SRC_TAG = "BTOP_XFER", CUSTOM_MC_MIN = "0", CUSTOM_MC_MAX = "2.75" *)
    reg [NBIT*(NSAMP_B_TOP)-1:0] bufferB_top = {NBIT*NSAMP_B_TOP{1'b0}};
    // bbot -4=-2.667 ns =-1, max 8 = 5.333 = 2
    (* CUSTOM_MC_SRC_TAG = "BBOT_XFER", CUSTOM_MC_MIN = "-1", CUSTOM_MC_MAX = "2" *)
    reg [NBIT*(NSAMP_B_BOT)-1:0] bufferB_bot = {NBIT*NSAMP_B_BOT{1'b0}};
    // third aclk buffer
    // ctop = -2 (-1.333 ns=-0.5), 10 (6.667=2.5)
    (* CUSTOM_MC_SRC_TAG = "CTOP_XFER", CUSTOM_MC_MIN = "-0.5", CUSTOM_MC_MAX = "2.5" *)
    reg [NBIT*(NSAMP_C_TOP)-1:0] bufferC_top = {NBIT*NSAMP_C_TOP{1'b0}};
    // cbot -5 (-3.333 ns = -1.25), 7 (4.667 ns = 1.75)
    (* CUSTOM_MC_SRC_TAG = "CBOT_XFER", CUSTOM_MC_MIN = "-1.25", CUSTOM_MC_MAX = "1.75" *)
    reg [NBIT*(NSAMP_C_BOT)-1:0] bufferC_bot = {NBIT*NSAMP_C_BOT{1'b0}};

    // memclk buffer
    (* CUSTOM_MC_DST_TAG = "ATOP_XFER ABOT_XFER BTOP_XFER BBOT_XFER CTOP_XFER CBOT_XFER" *)
    reg [NBIT*NSAMP_MEM-1:0] write_data = {NBIT*NSAMP_MEM{1'b0}};
    
    always @(posedge aclk_i) begin
        // because aclk_sync_i indicates the first phase, when we reregister it,
        // it's the second phase.
        // with multiple syncs, things can screw up once but that's it.
        buffer_phase <= { buffer_phase[1], aclk_sync_i, buffer_phase[2] };
                
        // these buffers all get names to make the lookup in the constraints easier
        // the max_delay/min_delay constraints are actually mixed for each of them,
        // but it's just easier to select when they have different names.

        // it doesn't go A/B/C here because the name indicates what phase they
        // were LAUNCHED at so it's off by 1. e.g. bufferA is valid when buffer_phase[0]
        // is high, so it's captured by buffer_phase[2] high.
        if (buffer_phase[0]) begin
            bufferB_bot <= dat_i[0 +: NBIT*NSAMP_B_BOT];
            bufferB_top <= dat_i[NBIT*NSAMP_B_BOT +: NBIT*NSAMP_B_TOP];
        end        
        if (buffer_phase[1]) begin
            bufferC_bot <= dat_i[0 +: NBIT*NSAMP_C_BOT];
            bufferC_top <= dat_i[NBIT*NSAMP_C_BOT +: NBIT*NSAMP_C_TOP];
        end
        if (buffer_phase[2]) begin
            bufferA_bot <= dat_i[0 +: NBIT*NSAMP_A_BOT];
            bufferA_top <= dat_i[NBIT*NSAMP_A_BOT +: NBIT*NSAMP_A_TOP];
        end        
    end
    // remember our ticks go
    // 0, 4, 8
    // 0, 3, 6, 9
            
    
    // We define the inputs here so the scramble opt is easier to write.
    wire [NSAMP_MEM*NBIT-1:0] write_data_in[3:0];
    // if write_phase 0 this is tick 3
    // capture data launched at tick 4 (bufferB_top) and tick 8 (bufferC_bot)
    // => bufferB_top min_delay -1 tick max_delay 11 ticks
    // => bufferC_bot min_delay -5 tick max_delay 7 ticks            
    assign write_data_in[0] = { bufferC_bot, bufferB_top };
    // if write phase 1 this is tick 6
    // capture data launched at tick 8 (bufferC_top) and tick 0 (bufferA_bot)
    // => bufferC_top min_delay -2 tick max_delay 10 tick
    // => bufferA_bot min_delay -6 tick max_delay 6 tick
    assign write_data_in[1] = { bufferA_bot, bufferC_top };
    // if write phase 2 this is tick 9
    // capture data launched at tick 0 (bufferA_top)
    // => bufferA_top min_delay -3 tick max delay 9 tick
    assign write_data_in[2] = bufferA_top;
    // if write phase 3 this is tick 0
    // capture data launched at tick 4 (bufferB_bot)
    // => bufferB_bot min_delay -4 tick max delay 8 tick
    assign write_data_in[3] = bufferB_bot;

    // The scramble optimization is detailed in the event buffer readout.
    // It's only spelled out in the 8-sample assumption, which is fine.
    // these indicate WHAT WE WRITE on these phases, which means we need to move BACK
    // a phase for the scrambling.
    // phase 0 (capture phase 3): reference (unchanged)
    // phase 1 (capture phase 0): swap bits [23:0] with bits [47:24]
    // phase 2 (capture phase 1): swap bits [23:0] with bits [71:48]
    // phase 3 (capture phase 2): source bits [47:24] => dest bits [71:48]
    //                            source bits [71:48] => dest bits [23:0]
    //                            source bits [23:0] => dest bits [47:24]
    // so viewing from destination we want
    //                    { source[47:24], source[23:0], source[71:48] }
    // bits [23:0] = bits [47:24]
    //                            bits [47:24] = bits [71:48]
    //                            bits [71:48] = bits [23:0]
    // if clk0 has 28,29,2A, 2B,2C,2D
    //    clk1 has 2E,2F,30, 31,32,33
    //    clk2 has 34,35,36, 37,38,39
    //    clk3 has 3A,3B,3C, 3D,3E,3F
    // we want this to be written
    // 28 29 2A 2B 2C 2D 2E 2F
    // 30 31 32 33 34 35 36 37
    // 38 39 3A 3B 3C 3D 3E 3F
    // so the same bytes that write 2C/2D and 34/35 want 3C/3D
    // so clk3 wants bits[47:24] => [71:48]
    always @(posedge memclk_i) begin
        case (write_phase)
            0: write_data <= (SCRAMBLE_OPT == "TRUE") ? 
                { write_data_in[0][71:48], write_data_in[0][23:0], write_data_in[0][47:24]} :
                write_data_in[0];
            1: write_data <= (SCRAMBLE_OPT == "TRUE") ? 
                { write_data_in[1][23:0], write_data_in[1][47:24], write_data_in[1][71:48]} :
                write_data_in[1];
            2: write_data <= (SCRAMBLE_OPT == "TRUE") ? 
                { write_data_in[2][47:24], write_data_in[2][23:0], write_data_in[2][71:48]} :
                write_data_in[2];
            3: write_data <= write_data_in[3];
        endcase
        // memclk_sync_i indicates phase 0, so we reset to phase 1        
        if (memclk_sync_i) write_phase <= 2'd1;
        else write_phase <= write_phase + 1;
    end

    assign dat_o = write_data;
    
endmodule
