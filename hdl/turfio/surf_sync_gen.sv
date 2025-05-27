`timescale 1ns / 1ps
// The difficulty with the sync generation is that we're essentially maintaining a
// bunch of different phases.
// When rxclkx3/aclk are synchronized and ifclk is aligned, we have
//
// tick     aclk    aclk_sync   memclk  memclk_sync rxclk   
// 0        1       0           1       0           1
// 1        1       1           1       1           1
// 2        1       1           1       1           1
// 3        1       1           0       1           1
// 4        0       1           0       1           1
// 5        0       1           0       1           1
// 6        0       1           1       1           1
// 7        0       1           1       0           1
// 8        1       1           1       0           1
// 9        1       0           0       0           1
// 10       1       0           0       0           1
// 11       1       0           0       0           1
// 12       0       0           1       0           0
// 13       0       0           1       0           0
// 14       0       0           1       0           0
// 15       0       0           0       0           0
// 16       1       0           0       0           0
// 17       1       0           0       0           0
// 18       1       0           1       0           0
// 19       1       0           1       0           0
// 20       0       0           1       0           0
// 21       0       0           0       0           0
// 22       0       0           0       0           0
// 23       0       0           0       0           0
//
// If you look at rxclk_aclk_transfer,
// we get NEW DATA in the aclk domain in the clock BEFORE
// aclk_sync.
// The bitslip module adds 1 clock of latency (always)
// and so we *always* should get a command_valid_i
// when aclk_sync_i is high, conveniently!
// sync_offset_i is an offset in __aclk sync periods__
// because sync periods *must* start on
// aclk sync boundaries.
// So in other words when we identify a SYNC
// command, we set "sync_seen" (which occurs
// on the clock after aclk_sync)
// and then every aclk_sync we increment
// a counter and sync_o is
// aclk_sync && (sync_offset_counter == sync_offset_i) && sync_seen
//
// If enable_sysref_count_i is set, we count the number
// of aclk clocks from sync -> sysref.
// Enable_sysref_count doesn't need to be high though,
// basically you only need to verify *once* at power-on.
// After that syncs (to reset counters) are fine on their own.
//
// OK: Just to make things simpler, we're going to mimic what's done in the TURFIO here.
// This means that the sync output will mimic the TURFIO once properly aligned, which
// will mimic the SYSREF, etc., and then we can also use it to control the phase of
// the COUT interface so everything has the same phase.
// Figure out the other clock domains in a bit.
module surf_sync_gen(
        input           aclk_i,
        input           aclk_phase_i,
        // this is a stretched signal occuring in aclk phase 1/3
        // each dest needs qualifier tags
        input           sync_req_i,
        input [4:0]     sync_offset_i,
        input           memclk_i,
        input           memclk_phase_i,
        input           ifclk_i,

        // debug
        output [1:0]    dbg_sync_o,

        // these are always running.
        // shouldn't be a problem, I'm not even sure what these
        // would ever get used for.
        // aclk domain
        output          sync_o,
        // sysref can be used as a verifier on PL_SYSREF I guess?
        // might be off by a clock though.    
        output          sysref_o,
        // memclk domain
        output          sync_memclk_o,
        // ifclk domain.
        output          sync_ifclk_o                
    );
    parameter [4:0] SYNC_OFFSET_DEFAULT = 7;
    parameter ACLKTYPE = "SYSREFCLK";
    parameter IFCLKTYPE = "IFCLK";
    parameter USE_IOB = "TRUE";
    parameter USE_IOB2 = "TRUE";    
    // this does. not. matter.
    (* CUSTOM_CC_DST = IFCLKTYPE *)
    reg [4:0] sync_offset_ifclk = SYNC_OFFSET_DEFAULT;
    
    // capture rundo_sync in ifclk.
    (* CUSTOM_MC_DST_TAG = "RUNDO_SYNC" *)
    reg rundo_sync_ifclk = 0;
    
    // ifclk phase counter. Copied from TURFIO.
    reg [4:0] clk_phase_counter = {5{1'b0}};    

    // this indicates the *next* ifclk cycle should
    // have sync = 1. We use this multiple places so we register it.
    // Normally sync would toggle on clk_phase_counter[3:0] == 15
    // so this is high on clk_phase_counter == 14.
    // These are always specified in source clock periods.
    (* CUSTOM_MC_SRC_TAG = "SYNC", CUSTOM_MC_MIN = "0.0", CUSTOM_MC_MAX = "1.0" *)
    reg sync_is_next = 0;
        
    // debug, for visibility
    (* IOB = USE_IOB *)
    reg debug_sync = 0;
    (* IOB = USE_IOB2 *)
    reg debug_sync2 = 0;
    
    wire do_sync_out;
    SRLC32E u_syncdelay(.D(rundo_sync_ifclk),
                        .CE(1'b1),
                        .CLK(ifclk_i),
                        .A(sync_offset_ifclk),
                        .Q(do_sync_out));

    // *complete* mimic of the TURFIO code, which
    // we know replicates the SURF clock. So this
    // could actually be used as the PL SYSREF.
    always @(posedge ifclk_i) begin
        rundo_sync_ifclk <= sync_req_i;
        
        sync_offset_ifclk <= sync_offset_i;

        sync_is_next <= (clk_phase_counter == 14);
        
        if (do_sync_out) clk_phase_counter <= {4{1'b0}};
        else clk_phase_counter <= clk_phase_counter[3:0] + 1;
               
        if (sync_is_next) debug_sync <= 1;
        else if (clk_phase_counter[3:0] == 7) debug_sync <= 0;

        if (sync_is_next) debug_sync2 <= 1;
        else if (clk_phase_counter[3:0] == 7) debug_sync2 <= 0;
    end
    
    assign dbg_sync_o = { debug_sync2, debug_sync};

    // in aclk, we just need to phase track: aclk_phase_i
    // is phase 1, so we need to delay by 2.
    reg [1:0] aclk_phase_buf = {2{1'b0}};
    // then we can do just clock aclk_phase_buf[2] && sync_is_next.
    (* CUSTOM_MC_DST_TAG = "SYNC" *)
    reg aclk_sync = 0;
    (* CUSTOM_MC_DST_TAG = "SYNC" *)
    reg aclk_sysref = 0;
    // consider if we wanted aclk_sysref to be 4 clocks long
    // clk  aclk_phase  sync_is_next    aclk_sysref aclk_sync   shreg
    // 0    001         0               0           0           0
    // 1    010         0               0           0           0
    // 2    100         0               0           0           0
    // 3    001         1               0           0           0
    // 4    010         1               0           0           0
    // 5    100         1               0           0           0
    // 6    001         0               1           1           000
    // 7    010         0               1           0           001     A=0
    // 8    100         0               1           0           010     A=1
    // 9    001         0               1           0           100     A=2
    // so the SRL address needs to be 2 less than as long as we want aclk_sysref high for.
    localparam ACLK_SYSREF_LEN = 24;
    localparam [4:0] ACLK_SYSREF_DELAY_SHREG = ACLK_SYSREF_LEN-2;
    wire aclk_clear_sysref;
    SRLC32E u_aclk_sync_delay(.D(aclk_sync),.A(ACLK_SYSREF_DELAY_SHREG),.CLK(aclk_i),
                              .CE(1'b1),.Q(aclk_clear_sysref));

    always @(posedge aclk_i) begin
        aclk_phase_buf <= { aclk_phase_buf[0], aclk_phase_i };
        aclk_sync <= aclk_phase_buf[1] && sync_is_next;
        if (aclk_phase_buf[1] && sync_is_next) aclk_sysref <= 1;
        else if (aclk_clear_sysref) aclk_sysref <= 0;
    end

    // and ditto for memclk, although we don't need a sysref there.
    reg [2:0] memclk_phase_buf = {3{1'b0}};
    (* CUSTOM_MC_DST_TAG = "SYNC" *)
    reg memclk_sync = 0;
    
    always @(posedge memclk_i) begin
        memclk_phase_buf <= { memclk_phase_buf[1:0], memclk_phase_i };
        memclk_sync <= memclk_phase_buf[2] && sync_is_next;
    end

    assign sync_o = aclk_sync;
    assign sysref_o = aclk_sysref;
    assign sync_memclk_o = memclk_sync;
    assign sync_ifclk_o = clk_phase_counter[4];
 
//    // ok: sync_req_i comes in running ACLK (375 MHz).
//    // but it's from the command decoder, 
    
//    // OKAY: THE DUMB METHOD
//    // We need to try to keep this simple since we only have 3 clocks to handle things.
//    // This means that what we're going to do is feed sync_req_i into an SRL
//    // with the sync offset fed into it, and aclk_phase_i as the clock enable.
//    // This means it pops out (offset_done) ready to go the clock AFTER aclk_phase_i.
//    //
//    // clk  aclk_phs    sync_req    offset_done     aclk_phs_buf[0]     next_do_sync    sync_o
//    // 0    1           1           0               0                   0               0
//    // 1    0           0           1               1                   0               0
//    // 2    0           0           1               0                   1               0
//    // 3    1           0           1               0                   0               1
//    // 4    0           0           0               1                   0               0
//    //
//    // nominally the issue we have with memclk is that next_do_sync rises at -1/3 memclk
//    // (at tick 8, with memclk's rising edge at 9). But it's qualified by memclk_phase_i
//    // as a CE so it's a multicycle constraint.
//    // Xilinx's tools align the clocks to have the worst case, so
//    // aclk rises at 0, rises again at 2.667, and at 5.33, then at 8, etc.
//    // (going backwards: -2.667, -5.333)
//    // memclk rises at 0.667 ns, again at 2.667, then at 4.667 then at 6.667, etc. 
//    // (going backwards: -1.333, -3.333, -5.333, -7.333)
//    // so what we need to do is move the setup constraint forward 1
//    // and the hold constraint then needs to move back 5.
//    // so set_multicycle_path -setup -end 1
//    //    set_multicycle_path -hold -end 5
     
//    // ifclk doesn't need anything, it should properly align.
//    // the sync offset here is just going to have a datapath only constraint
//    wire offset_done;
//    (* CUSTOM_CC_DST = ACLKTYPE *)
//    SRLC32E u_sync_delay(.CLK(aclk_i),.CE(aclk_phase_i),
//                         .A(sync_offset_i),
//                         .D(sync_req_i),
//                         .Q(offset_done));
//    (* SYNC_MCP_SRC = "TRUE", CUSTOM_CC_DST = ACLKTYPE *)
//    reg next_do_sync = 0;
//    reg sync = 0;
//    (* SYNC_MCP_DST = "TRUE", KEEP = "TRUE" *)
//    reg memclk_sync = 0;
//    reg ifclk_sync = 0;
    
//    reg [5:0] sysref_phase = {6{1'b0}};
//    reg aclk_phase_buf = 1'b0;

//    always @(posedge aclk_i) begin
//        //if (sync_o) sysref_phase <= 
//        // aclk_sync_buf[1] high indicates aclk_sync_i will go next        
//        aclk_phase_buf <= aclk_phase_i;

//        next_do_sync <= offset_done && aclk_phase_buf;
//        sync <= next_do_sync;
//    end
//    always @(posedge memclk_i) begin
//        if (memclk_phase_i) memclk_sync <= next_do_sync;
//    end
    
//    always @(posedge ifclk_i) begin
//        ifclk_sync <= next_do_sync;
//    end

//    assign sync_o = sync;
//    assign sync_memclk_o = memclk_sync;
//    assign sync_ifclk_o = ifclk_sync;    
    
endmodule
