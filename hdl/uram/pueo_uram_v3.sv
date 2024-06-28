`timescale 1ns / 1ps
// the ZU25 has 48 URAM blocks per. Each channel needs 96 bits: URAMs are quantized in units of 72.
// We handle this by jumping to a 500 MHz domain.
// Each URAM handles 24k samples, since each one is groups of 6. This is 8 us. So we use 4 each at first,
// requiring an address length of 14 bits, or 16384*6 = 98,304 samples = 32.768 us. We can double
// that for the ZU47DR.
//
// Note that we measure things here in "ticks" of 2/3 of a ns. In those units,
// memclk is 3 ticks, aclk is 4 ticks.
//
// THE V3 MODULE - WE NEVER ACTUALLY FINISHED THE V2 MODULE
// This module implements ALL of the goddamn channels in ONE
// chained URAM. It does NOT use the dumbass XPM macros
// which are just dogshit.
//
// There is an additional parameter here called SCRAMBLE_OPT
// which scrambles the samples on clock transfer to
// simplify the readout.
//
// NOTE: The timing here is fixed, so this module has to match the
// event buffer.
//
// With READOUT_PHASE = 0, begin_o pops out on phase 1
// and the data valid for channel 0 pops out on phase 3 one full phase later
// e.g.
// clk  phase   begin_o valid[0]
// 0    3       0       0
// 1    0       0       0
// 2    1       1       0
// 3    2       0       0
// 4    3       0       0
// 5    0       0       0
// 6    1       0       0
// 7    2       0       0
// 8    3       0       1
// Every other channel is delayed by 2 clocks for each channel.
//
//
// NOTE: ADDRLEN here is the length of the *internal* address bus
// (the MEMCLK address).
// ADDRBITS is the width of s_axis_tdata (the AXI4-Stream path):
// it is aligned to LOOK like the MEMCLK address but the bottom
// 2 bits are ALWAYS IGNORED because we have to READ ON A 4-SAMPLE
// BOUNDARY.
module pueo_uram_v3 #(
                   parameter NCHAN=8,
                   parameter NSAMP=8,
                   parameter NBIT=12,
                   // this should be number of samples/6 rounded UP                   
                   parameter RDLEN=171,
                   parameter ADDRLEN=14,
                   parameter ADDRBITS=16,
                   parameter SCRAMBLE_OPT = "TRUE",
                   parameter READOUT_PHASE = 0)(
        input aclk,
        input aclk_sync_i,
        input aclk_rst_i,
        input [NCHAN*NSAMP*NBIT-1:0] dat_i,

        input memclk,
        input memclk_sync_i,

        // input REQUEST
        input [ADDRBITS-1:0] s_axis_tdata,
        input                s_axis_tvalid,
        output               s_axis_tready,

        // output data.
        // I need to figure out exactly
        // what the latency should be here.
        output begin_o,
        output [NCHAN*(NSAMP*3/4)*NBIT-1:0] dat_o,
        output [NCHAN-1:0] dat_valid_o
    );
    
    localparam NUM_URAM = 1<<(ADDRLEN-12);
    localparam MEM_SIZE = 72*(1<<ADDRLEN);

    localparam RDCNTLEN = $clog2(RDLEN);            

    localparam NMEMSAMP = NSAMP*3/4;
    
    reg               aclk_reset_seen = 0;
    reg [1:0]         aclk_reset = 2'b00;

    reg               write_reset = 0;
    reg               running = 0;
    
    reg reading = 0;
    reg read_start = 0;
    wire read_complete;
    wire read_active;
    wire [ADDRLEN-1:0] read_addr;
        
    reg [2:0] aclk_phase = {3{1'b0}};
    reg [3:0] memclk_phase = {4{1'b0}};
    always @(posedge aclk) begin
        aclk_phase <= { aclk_phase[1], aclk_sync_i, aclk_phase[2] };

        if (aclk_reset[0]) aclk_reset_seen <= 1'b0;
        else if (aclk_rst_i) aclk_reset_seen <= 1'b1;
        // aclk_reset[0] now goes high in phase 1 (tick 4) and low in phase 0 (tick 0)
        // it's qualified by memclk phase 2, so captured at tick 9
        // so min delay -3, max delay 5 (b/c it's high for 8 ticks)
        // the memclk reset then goes high in 3, and resets at the same phase 0
        // as aclk_reset[1] indicates.
        // phase    aclk_reset_seen     aclk_reset[0]   aclk_reset[1]
        // 0        0                   0               0
        // 1        1                   0               0
        // 2        1                   0               0
        // 0        1                   0               0
        // 1        1                   1               0
        // 2        0                   1               1
        // 0        0                   0               0
        // the 2-clock stretch is needed.
        if (aclk_phase[0]) aclk_reset[0] <= aclk_reset_seen;
        else if (aclk_phase[2]) aclk_reset[0] <= 1'b0;
        
        aclk_reset[1] <= aclk_reset[0] && aclk_reset_seen;
    end

    always @(posedge memclk) begin
        memclk_phase <= { memclk_phase[2:1], memclk_sync_i, memclk_phase[3] };
        // this might be too hard: we might need to be more clever
        write_reset <= memclk_phase[2] && aclk_reset[0];
        if (write_reset) running <= 1'b1;        

        // we need to align the readout to the memclk_phase.
        // This means we end up taking a little longer to read out
        // than we did to write in, but the amount is small.
        // It doesn't actually really matter *what phase* we align
        // to, we just have to KNOW what it is.

        if (read_complete) reading <= 1'b0;
        else if (s_axis_tvalid && s_axis_tready) reading <= 1'b1;
        
        read_start <= (s_axis_tvalid && s_axis_tready);
    end
    // trim the bottom 2 bits and force them to 0.
    uram_read_counter #(.COUNT_MAX(RDLEN),
                        .ADDR_BITS(ADDRLEN))
        u_counter( .clk_i(memclk),
                    .start_addr_i( {s_axis_tdata[2 +: (ADDRLEN-2)],2'b00} ),
                    .run_i(read_start),
                    .addr_valid_o(read_active),
                    .addr_o(read_addr),
                    .complete_o(read_complete));                        

    // ok here we go
    wire [NSAMP*NBIT-1:0] sync_data_in[NCHAN-1:0];
    wire [NMEMSAMP*NBIT-1:0] uram_data_in[NCHAN-1:0];
    wire [NMEMSAMP*NBIT-1:0] uram_data_out[NCHAN-1:0];
    wire [NCHAN-1:0] uram_rdaccess;
    // MOUNTAIN OF CASCADES
    // THESE ARE ONLY *BETWEEN CHANNEL* CASCADES
    // INTERNAL ONES ARE INTERNAL (duh)
    `define DEFINE_URAM_CASCADE_VEC( name, len , dir, ch )    \
        wire [22:0] name``cas_``dir``_addr_``ch [ len - 1:0];  \
        wire [8:0] name``cas_``dir``_bwe_``ch [ len - 1:0];    \
        wire name``cas_``dir``_dbiterr_``ch [ len - 1:0];      \
        wire [71:0] name``cas_``dir``_din_``ch [ len - 1:0];   \
        wire [71:0] name``cas_``dir``_dout_``ch [ len - 1:0];  \
        wire name``cas_``dir``_en_``ch [ len - 1:0];           \
        wire name``cas_``dir``_rdaccess_``ch [ len - 1:0];     \
        wire name``cas_``dir``_rdb_wr_``ch [ len - 1:0];       \
        wire name``cas_``dir``_sbiterr_``ch [ len - 1:0]
        
    `define DEFINE_URAM_FULL_CASCADE_VEC( name, len ) \
        `DEFINE_URAM_CASCADE_VEC( name, len , in , a );   \
        `DEFINE_URAM_CASCADE_VEC( name, len , in , b );   \
        `DEFINE_URAM_CASCADE_VEC( name, len , out , a );  \
        `DEFINE_URAM_CASCADE_VEC( name, len , out , b )  

    `define HOOKUP_URAM_CASCADE_HELPER( inname , outname, chinsuffix, choutsuffix )   \
        assign inname``cas_in_addr_``chinsuffix = outname``cas_out_addr_``choutsuffix;   \
        assign inname``cas_in_bwe_``chinsuffix = outname``cas_out_bwe_``choutsuffix;     \
        assign inname``cas_in_dbiterr_``chinsuffix = outname``cas_out_dbiterr_``choutsuffix; \
        assign inname``cas_in_din_``chinsuffix = outname``cas_out_din_``choutsuffix; \
        assign inname``cas_in_dout_``chinsuffix = outname``cas_out_dout_``choutsuffix; \
        assign inname``cas_in_en_``chinsuffix = outname``cas_out_en_``choutsuffix; \
        assign inname``cas_in_rdaccess_``chinsuffix = outname``cas_out_rdaccess_``choutsuffix; \
        assign inname``cas_in_rdb_wr_``chinsuffix = outname``cas_out_rdb_wr_``choutsuffix; \
        assign inname``cas_in_sbiterr_``chinsuffix = outname``cas_out_sbiterr_``choutsuffix

    `define HOOKUP_URAM_CASCADE( inname, outname, ch, insuffix, outsuffix )    \
        `HOOKUP_URAM_CASCADE_HELPER( inname, outname, ch``insuffix , ch``outsuffix )

    // goddamn it
    // horrible metaprogramming hacks
    `define URAM_PORT( name, dir, ch) .CAS_``dir``name``ch
    
    `define CONNECT_URAM_CASC_VEC_HELPER( name, dir, chsuffix, udir, uch)    \
        `URAM_PORT( _ADDR_ , udir, uch) ( name``cas_``dir``_addr_``chsuffix ),  \
        `URAM_PORT( _BWE_ , udir, uch) ( name``cas_``dir``_bwe_``chsuffix ),           \
        `URAM_PORT( _DBITERR_ , udir, uch) ( name``cas_``dir``_dbiterr_``chsuffix ),  \
        `URAM_PORT( _DIN_ , udir, uch) ( name``cas_``dir``_din_``chsuffix ), \
        `URAM_PORT( _DOUT_ , udir, uch) ( name``cas_``dir``_dout_``chsuffix ), \
        `URAM_PORT( _EN_ , udir, uch) ( name``cas_``dir``_en_``chsuffix ), \
        `URAM_PORT( _RDACCESS_, udir, uch) ( name``cas_``dir``_rdaccess_``chsuffix ), \
        `URAM_PORT( _RDB_WR_, udir, uch) ( name``cas_``dir``_rdb_wr_``chsuffix ), \
        `URAM_PORT( _SBITERR_, udir, uch) ( name``cas_``dir``_sbiterr_``chsuffix )        

    `define CONNECT_URAM_ACASCIN_VEC( name, suffix)  \
        `CONNECT_URAM_CASC_VEC_HELPER( name, in, a``suffix, IN, A )
    `define CONNECT_URAM_ACASCOUT_VEC( name, suffix)  \
        `CONNECT_URAM_CASC_VEC_HELPER( name, out, a``suffix, OUT, A )
    `define CONNECT_URAM_BCASCIN_VEC( name, suffix)  \
        `CONNECT_URAM_CASC_VEC_HELPER( name, in, b``suffix, IN, B )
    `define CONNECT_URAM_BCASCOUT_VEC( name, suffix)  \
        `CONNECT_URAM_CASC_VEC_HELPER( name, out, b``suffix, OUT, B )
        
    // the NCHAN+1 is for stupidity
    `DEFINE_URAM_FULL_CASCADE_VEC( uram_ , NCHAN );    

    generate
        genvar i;
        for (i=0;i<NCHAN;i=i+1) begin : CH
            assign sync_data_in[i] = dat_i[NSAMP*NBIT*i +: NSAMP*NBIT];
            uram_sync_transfer #(.SCRAMBLE_OPT(SCRAMBLE_OPT))
                               u_transfer(.aclk_i(aclk),
                                          .aclk_sync_i(aclk_sync_i),
                                          .memclk_i(memclk),
                                          .memclk_sync_i(memclk_sync_i),
                                          .dat_i(sync_data_in[i]),
                                          .dat_o(uram_data_in[i]));
            // now the INTERNAL ones
            `DEFINE_URAM_FULL_CASCADE_VEC( int_ , NUM_URAM );
            // channel A is used for writing, B for readout
            assign int_cas_in_addr_a[0] = {23{1'b0}};
            assign int_cas_in_bwe_a[0] = {9{1'b0}};
            assign int_cas_in_dbiterr_a[0] = 1'b0;
            assign int_cas_in_din_a[0] = {72{1'b0}};
            assign int_cas_in_dout_a[0] = {72{1'b0}};
            assign int_cas_in_en_a[0] = 1'b0;
            assign int_cas_in_rdaccess_a[0] = 1'b0;
            assign int_cas_in_rdb_wr_a[0] = 1'b0;
            assign int_cas_in_sbiterr_a[0] = 1'b0;
            // terminate B only if we're channel 0
            assign int_cas_in_addr_b[0]        = (i == 0) ? {23{1'b0}} : uram_cas_out_addr_b[i-1];
            assign int_cas_in_bwe_b[0]         = (i == 0) ? {9{1'b0}} : uram_cas_out_bwe_b[i-1];
            assign int_cas_in_dbiterr_b[0]     = (i == 0) ? 1'b0 : uram_cas_out_dbiterr_b[i-1];
            assign int_cas_in_din_b[0]         = (i == 0) ? {72{1'b0}} : uram_cas_out_din_b[i-1];
            assign int_cas_in_dout_b[0]        = (i == 0) ? {72{1'b0}} : uram_cas_out_dout_b[i-1];
            assign int_cas_in_en_b[0]          = (i == 0) ? 1'b0 : uram_cas_out_en_b[i-1];
            assign int_cas_in_rdaccess_b[0]    = (i == 0) ? 1'b0 : uram_cas_out_rdaccess_b[i-1];
            assign int_cas_in_rdb_wr_b[0]      = (i == 0) ? 1'b0 : uram_cas_out_rdb_wr_b[i-1];
            assign int_cas_in_sbiterr_b[0]     = (i == 0) ? 1'b0 : uram_cas_out_sbiterr_b[i-1];

            // inname, outname, ch, insuffix, outsuffix
            `HOOKUP_URAM_CASCADE( int_ , int_ , a, [1], [0]);
            `HOOKUP_URAM_CASCADE( int_ , int_ , b, [1], [0]);
            `HOOKUP_URAM_CASCADE( int_ , int_ , a, [2], [1]);
            `HOOKUP_URAM_CASCADE( int_ , int_ , b, [2], [1]);
            `HOOKUP_URAM_CASCADE( int_ , int_ , a, [3], [2]);
            `HOOKUP_URAM_CASCADE( int_ , int_ , b, [3], [2]);

            // We might be able to use a single shared counter for the top bits
            // and reregister or something. Helpful thing is that
            // because we always reset at phase 0 the low 2 bits are ALWAYS
            // the same thing as the phase counter in the sync transfer.
            reg [ADDRLEN-1:0] write_addr = {ADDRLEN{1'b0}};
            reg sleeping = 1;
            
            always @(posedge memclk) begin
                sleeping <= ~running;
                if (write_reset) write_addr <= {ADDRLEN{1'b0}};
                else write_addr <= write_addr + 1;
            end
            
            // OK: FIRST ATTEMPT
            // The only addresses which get passed up the BRAM chain
            // are the upper addresses, which only change every 4 writes.
            // If we set this up such that *every channel* is offset
            // by 4 writes, they can just *pass the data up* and
            // it'll naturally delay.
            localparam FIRST_CASCADE_ORDER_B = (i == 0) ? "FIRST" : "MIDDLE";
            localparam LAST_CASCADE_ORDER_B = (i == NCHAN-1) ? "MIDDLE" : "LAST";

            localparam REG_CAS_B_START = "TRUE";
            localparam REG_CAS_B_MID0 = "TRUE";
            localparam REG_CAS_B_MID1 = "TRUE";
            localparam REG_CAS_B_END = "TRUE";
            
            wire [22:0] this_write_addr = { {(23-ADDRLEN){1'b0}}, write_addr };
            wire [22:0] this_read_addr = { {(23-ADDRLEN){1'b0}}, read_addr };
            
            
            // SCREW IT I'M NOT MAKING THIS PARAMETERIZABLE RIGHT NOW WILL FIX LATER
            URAM288 #( .CASCADE_ORDER_A("FIRST"),
                       .CASCADE_ORDER_B(FIRST_CASCADE_ORDER_B),
                       .IREG_PRE_A("TRUE"),
                       .IREG_PRE_B(FIRST_CASCADE_ORDER_B == "FIRST" ? "TRUE" : "FALSE"),
                       .NUM_UNIQUE_SELF_ADDR_A(NUM_URAM),
                       .NUM_UNIQUE_SELF_ADDR_B(NUM_URAM),
                       .OREG_A("FALSE"),
                       .OREG_B("TRUE"),
                       .REG_CAS_A("FALSE"),
                       .REG_CAS_B(REG_CAS_B_START),
                       .SELF_ADDR_A(11'h000),
                       .SELF_ADDR_B(11'h000),
                       .SELF_MASK_A(11'h7FC),
                       .SELF_MASK_B(11'h7FC))
                       u_urama(.DIN_A( uram_data_in[i] ),
                               .ADDR_A( this_write_addr ),
                               // whatever
                               .EN_A( 1'b1 ),
                               .RDB_WR_A( 1'b1 ),
                               .BWE_A( {9{1'b1}} ),
                               .INJECT_SBITERR_A(1'b0),
                               .INJECT_DBITERR_A(1'b0),
                               .OREG_CE_A(1'b0),
                               .OREG_ECC_CE_A(1'b0),
                               .RST_A(1'b0),
                               .SLEEP(sleeping),
                               .CLK( memclk ),
                               // no din_b
                               .DIN_B( {72{1'b0}} ),
                               .ADDR_B( (i==0) ? this_read_addr : 1'b0 ),
                               .EN_B( (i == 0) ? read_active : 1'b0 ),
                               .RDB_WR_B( 1'b0 ),
                               .BWE_B( {9{1'b0}} ),
                               .INJECT_SBITERR_B(1'b0),
                               .INJECT_DBITERR_B(1'b0),
                               .OREG_CE_B(1'b1),
                               .OREG_ECC_CE_B(1'b0),
                               .RST_B(1'b0),
                               `CONNECT_URAM_ACASCIN_VEC( int_ , [0] ),
                               `CONNECT_URAM_ACASCOUT_VEC( int_ , [0] ),
                               `CONNECT_URAM_BCASCIN_VEC( int_ , [0] ),
                               `CONNECT_URAM_BCASCOUT_VEC( int_ , [0] ));
            URAM288 #( .CASCADE_ORDER_A("MIDDLE"),
                       .CASCADE_ORDER_B("MIDDLE"),
                       .IREG_PRE_A("FALSE"),
                       .IREG_PRE_B("FALSE"),
                       .NUM_UNIQUE_SELF_ADDR_A(NUM_URAM),
                       .NUM_UNIQUE_SELF_ADDR_B(NUM_URAM),
                       .OREG_A("FALSE"),
                       .OREG_B("TRUE"),
                       .REG_CAS_A("FALSE"),
                       .REG_CAS_B(REG_CAS_B_MID0),
                       .SELF_ADDR_A(11'h001),
                       .SELF_ADDR_B(11'h001),
                       .SELF_MASK_A(11'h7FC),
                       .SELF_MASK_B(11'h7FC))
                       u_uramb(.SLEEP(sleeping),
                               .CLK( memclk ),
                               `CONNECT_URAM_ACASCIN_VEC( int_ , [1] ),
                               `CONNECT_URAM_ACASCOUT_VEC( int_ , [1] ),
                               `CONNECT_URAM_BCASCIN_VEC( int_ , [1] ),
                               `CONNECT_URAM_BCASCOUT_VEC( int_ , [1] ));
            URAM288 #( .CASCADE_ORDER_A("MIDDLE"),
                       .CASCADE_ORDER_B("MIDDLE"),
                       .IREG_PRE_A("FALSE"),
                       .IREG_PRE_B("FALSE"),
                       .NUM_UNIQUE_SELF_ADDR_A(NUM_URAM),
                       .NUM_UNIQUE_SELF_ADDR_B(NUM_URAM),
                       .OREG_A("FALSE"),
                       .OREG_B("TRUE"),
                       .REG_CAS_A("FALSE"),
                       .REG_CAS_B(REG_CAS_B_MID1),
                       .SELF_ADDR_A(11'h002),
                       .SELF_ADDR_B(11'h002),
                       .SELF_MASK_A(11'h7FC),
                       .SELF_MASK_B(11'h7FC))
                       u_uramc(.SLEEP(sleeping),
                               .CLK( memclk ),
                               `CONNECT_URAM_ACASCIN_VEC( int_ , [2] ),
                               `CONNECT_URAM_ACASCOUT_VEC( int_ , [2] ),
                               `CONNECT_URAM_BCASCIN_VEC( int_ , [2] ),
                               `CONNECT_URAM_BCASCOUT_VEC( int_ , [2] ));
            // The last bits SHOULD be okay being connected because they float
            URAM288 #( .CASCADE_ORDER_A("LAST"),
                       .CASCADE_ORDER_B(LAST_CASCADE_ORDER_B),
                       .IREG_PRE_A("FALSE"),
                       .IREG_PRE_B("FALSE"),
                       .NUM_UNIQUE_SELF_ADDR_A(NUM_URAM),
                       .NUM_UNIQUE_SELF_ADDR_B(NUM_URAM),
                       .OREG_A("FALSE"),
                       .OREG_B("TRUE"),
                       .REG_CAS_A("FALSE"),
                       // REG_CAS_B should be TRUE here
                       // because we might cross clock boundaries.
                       .REG_CAS_B(REG_CAS_B_END),
                       .SELF_ADDR_A(11'h003),
                       .SELF_ADDR_B(11'h003),
                       .SELF_MASK_A(11'h7FC),
                       .SELF_MASK_B(11'h7FC))
                       u_uramd(.SLEEP(sleeping),
                               .CLK( memclk ),
                               .DOUT_B( uram_data_out[i] ),
                               .RDACCESS_B( uram_rdaccess[i] ),
                               `CONNECT_URAM_ACASCIN_VEC( int_ , [3] ),
                               `CONNECT_URAM_BCASCIN_VEC( int_ , [3] ),
                               `CONNECT_URAM_BCASCOUT_VEC( uram_ , [i] ));

            assign dat_o[((NSAMP*3/4)*NBIT)*i +: (NSAMP*3/4)*NBIT] = uram_data_out[i];
        end            
    endgenerate            

    
    assign begin_o = read_start;
    assign dat_valid_o = uram_rdaccess;
    
    // this means we toggle weirdly but it doesn't matter
    assign s_axis_tready = !reading && memclk_phase[READOUT_PHASE];
endmodule
