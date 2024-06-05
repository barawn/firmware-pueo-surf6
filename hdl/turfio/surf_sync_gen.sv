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
module surf_sync_gen(
        input           aclk_i,
        input           aclk_phase_i,
        input           sync_req_i,
        input [4:0]     sync_offset_i,
        input           memclk_i,
        input           memclk_phase_i,
        input           ifclk_i,

        // aclk domain
        output          sync_o,        
        // memclk domain
        output          sync_memclk_o,
        // ifclk domain
        output          sync_ifclk_o                
    );
    
    parameter ACLKTYPE = "SYSREFCLK";
    
    // OKAY: THE DUMB METHOD
    // We need to try to keep this simple since we only have 3 clocks to handle things.
    // This means that what we're going to do is feed sync_req_i into an SRL
    // with the sync offset fed into it, and aclk_phase_i as the clock enable.
    // This means it pops out (offset_done) ready to go the clock AFTER aclk_phase_i.
    //
    // clk  aclk_phs    sync_req    offset_done     aclk_phs_buf[0]     next_do_sync    sync_o
    // 0    1           1           0               0                   0               0
    // 1    0           0           1               1                   0               0
    // 2    0           0           1               0                   1               0
    // 3    1           0           1               0                   0               1
    // 4    0           0           0               1                   0               0
    //
    // nominally the issue we have with memclk is that next_do_sync rises at -1/3 memclk
    // (at tick 8, with memclk's rising edge at 9). But it's qualified by memclk_phase_i
    // as a CE so it's a multicycle constraint.
    // Xilinx's tools align the clocks to have the worst case, so
    // aclk rises at 0, rises again at 2.667, and at 5.33, then at 8, etc.
    // (going backwards: -2.667, -5.333)
    // memclk rises at 0.667 ns, again at 2.667, then at 4.667 then at 6.667, etc. 
    // (going backwards: -1.333, -3.333, -5.333, -7.333)
    // so what we need to do is move the setup constraint forward 1
    // and the hold constraint then needs to move back 5.
    // so set_multicycle_path -setup -end 1
    //    set_multicycle_path -hold -end 5
     
    // ifclk doesn't need anything, it should properly align.
    // the sync offset here is just going to have a datapath only constraint
    wire offset_done;
    (* CUSTOM_CC_DST = ACLKTYPE *)
    SRLC32E u_sync_delay(.CLK(aclk_i),.CE(aclk_phase_i),
                         .A(sync_offset_i),
                         .D(sync_req_i),
                         .Q(offset_done));
    (* SYNC_MCP_SRC = "TRUE", CUSTOM_CC_DST = ACLKTYPE *)
    reg next_do_sync = 0;
    reg sync = 0;
    (* SYNC_MCP_DST = "TRUE", KEEP = "TRUE" *)
    reg memclk_sync = 0;
    reg ifclk_sync = 0;
    
    reg [5:0] sysref_phase = {6{1'b0}};
    reg aclk_phase_buf = 1'b0;

    always @(posedge aclk_i) begin
        //if (sync_o) sysref_phase <= 
        // aclk_sync_buf[1] high indicates aclk_sync_i will go next        
        aclk_phase_buf <= aclk_phase_i;

        next_do_sync <= offset_done && aclk_phase_buf;
        sync <= next_do_sync;
    end
    always @(posedge memclk_i) begin
        if (memclk_phase_i) memclk_sync <= next_do_sync;
    end
    
    always @(posedge ifclk_i) begin
        ifclk_sync <= next_do_sync;
    end

    assign sync_o = sync;
    assign sync_memclk_o = memclk_sync;
    assign sync_ifclk_o = ifclk_sync;    
    
endmodule
