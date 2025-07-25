`timescale 1ns / 1ps
`include "interfaces.vh"
`define DLYFF #0.1
// URAM-to-Event buffer.
// This interfaces with pueo_uram_v3+ only!
//
// We don't need a memclk_sync here -
// pueo_uram_v3+ syncs up the readout requests
// to a phase, so begin_i always occurs in phase 1.
// It's the critical timing element.
//
// The goal here is to produce an output stream
// to feed into DOUT: we only need to output 1
// every 2 clocks, but the COBS encoding will
// end up buffering it anyway.
// With COBS the overhead is (n/254) rounded up, max:
// our data is 12,288 bytes meaning we'll pick up
// at most 49 bytes overhead. With 8 buffers that's
// 392 bytes at most. We also have the
// header as well, which is probably just going to be
//
// <event number> 4 bytes
// <event clock> 4 bytes
// so that's an additional 64 total bytes.
// Smallest FIFO we have is a single FIFO18
// which is 8x2048 so this isn't a problem.
//
// NOTE: rst_i is in memclk domain
//       ifclk_rst_i is in ifclk domain
//       Resets here need to be applied
//       -> assert ifclk reset
//       -> assert memclk reset
//       -> release memclk reset
//       -> release ifclk reset
//       and the resets obviously need to be held for a minimum # of clocks (16 is good enough for all of ours)
// We need an overall reset controller which sequences stuff. Our overall goal is to
// keep the reset inputs at each module as simple as possible and allow them to be pipelined.

// We also now generate an event header as well,
// containing a 2-byte event number and the 2-byte
// trigger time.
// We have a very small buffer here (16 entries, using
// distram) to hold the trigger time. Because the read
// into the event buffer takes macroscopic time (342 ns)
// there's no worry here, it will always be ready first.
//
// The annoying thing here is that it means we now need
// to register the final output to mux it, and we also have
// to wait for the data to finish outputting before we totally complete.
// WHATEVER.
//
// NOTE NOTE NOTE NOTE NOTE NOTE NOTE
// This module produces valid new data when syncclk_phase is HIGH
// tvalid is asserted then.
//
// THIS VERSION CAN ACTUALLY BE IMPLEMENTED:
// IT USES THE BRAM IN A STANDARD DATA OUTPUT CASCADE ONLY, NO PIPELINING
//
// THIS VERSION ACCEPTS DATA FROM NON-CASCADED URAMS
// SO AFTER BEGIN, THE ADDRESS IS JUST THE SAME FOR ALL OF THEM
module uram_event_buffer_v3 #(parameter NCHAN = 8,
                           parameter NBIT_IN = 72,
                           parameter BEGIN_PHASE = 1,
                           parameter DOUT_LATENCY = 6,
                           parameter DEBUG = "TRUE",
                           parameter MEMCLKTYPE = "NONE",
                           parameter IFCLKTYPE = "NONE")(
        input memclk_i,
        input memclk_rst_i,
        input begin_i,
        input [NBIT_IN*NCHAN-1:0] dat_i,
        input [NCHAN-1:0] dat_valid_i,
        input ifclk_rst_i,
        output write_error_o,
        // the input here just becomes valid every
        // other clock until the last
        input ifclk_i,
        // these are *aclk* not *memclk*
        input aclk_i,
        input aclk_rst_i,
        input [14:0] trig_time_i,
        input [15:0] event_no_i,
        input        trig_valid_i,
        // fw update stuff
        input [7:0]  fw_dat_i,
        input        fw_wr_i,
        input [1:0]  fw_mark_i,
        output [1:0] fwmon_wr_o,
        // comes from idctrl
        input        fw_load_i,
        // output data. 
        output [7:0] dout_data_o,
        output       dout_data_valid_o,
        output       dout_data_last_o,
        input        dout_data_phase_i
    );        
    // whatever!! I'll figure out write error later
    // or maybe never at all
    assign write_error_o = 1'b0;
    
    // NOTE: BEGIN_DELAY needs to be structured so that the address arrives
    // *** 1 AFTER *** THE DATA
    // THE DATA IS GOING TO BE DELAYED BY THE MUX/REREGISTER    
    localparam BEGIN_DELAY = 6;
    localparam [3:0] BEGIN_DELAY_VAL = (BEGIN_DELAY == 0) ? 0 : BEGIN_DELAY-1;
    wire begin_delayed;
    wire this_begin = (BEGIN_DELAY == 0) ? begin_i : begin_delayed;
    SRL16E u_begin_delay(.D(begin_i),
                         .CE(1'b1),
                         .CLK(memclk_i),
                         .A0(BEGIN_DELAY_VAL[0]),
                         .A1(BEGIN_DELAY_VAL[1]),
                         .A2(BEGIN_DELAY_VAL[2]),
                         .A3(BEGIN_DELAY_VAL[3]),
                         .Q(begin_delayed));
    
    // The details here are documented in the event buffer section
    // of the firmware documentation.
    // This is trickier than it first seems.
    
    // This version accepts URAM data coming in At The Same Time
    // Writing occurs at memclk speed (500 MHz), reading at ifclk speed (125 MHz)
    // So writing needs to be easy.
    
    // We write 3 addresses (24 samples) per 4 clock cycles.
    // We will ALWAYS get begin_i in phase 1.
    // Suppose we register begin_i: this will then go high in phase 2.
    // We then use this signal to reset the address generation, so it's reset in phase 3.
    // The timing of a 4-address increment will always be
    // 5/6/5 6/5/6
    // This pattern is generated by the uram_event_timer.
    // We generate a global next upper address which everyone sees. At 500 MHz
    // this might need to be either duplicated or re-registered. This shouldn't
    // cause a problem.
    
    // We'll fan this out here.
    wire [7:0] bram_uaddr[NCHAN-1:0];
    
    // the top 3 bits are the buffer. They're Gray encoded so they can
    // hop across domains. Thankfully a 3-bit Gray counter fits in logic.

    // This is the *in progress* buffer pointer.
    // This gets incremented when the first channel finishes.
    reg [2:0] write_buffer = {3{1'b0}};
    // This is the *completed* buffer pointer. This gets incremented
    // when the last channel finishes.
    (* CUSTOM_GRAY_SRC = MEMCLKTYPE, DONT_TOUCH = "TRUE" *)
    reg [2:0] complete_buffer_pointer = {3{1'b0}};
    // The reason we have 2 buffer pointers is because our control logic
    // is pipelined. We could probably just start reading out early,
    // but I'd rather be safe than sorry.
    
    // This is the upper address pointer.
    // We only pass the top 5 bits to the individual channels.
    reg [4:0] write_addr = {5{1'b0}};    
    reg [1:0] glob_memclk_phase = {2{1'b0}};
    localparam [1:0] GLOB_MEMCLK_PHASE_RESET_VAL = 3;
    wire glob_start;
    reg running = 0;
    wire increment_uaddr;
    uram_event_timer u_timer(.memclk_i(memclk_i),
                             .memclk_phase_i(!glob_memclk_phase[0]),
                             .running_i(running),
                             .start_o(glob_start),
                             .capture_o(increment_uaddr));
    // ok we still need to figure out when to *terminate* running
    localparam TERMINATE_VAL = {5{1'b1}};
    // and then once we hit that point, we need
    // to delay the terminate slightly to line everything
    // up. The URAM reads out 1026 samples: looking at the
    // physical transition flow you can see that it'll
    // be phase 3 that we stop at, because the 'stored'
    // A0/A1/A2 data (2 samples) will be discarded.
    // If you work out the logic you'd *expect* this to be 2
    // but the extra clock comes because we don't increment
    // in phase 1.
    //
    // Working it out, after this_begin goes high,
    // the next this_begin cannot occur for another 350 ns,
    // or 175 clocks: in other words, we add *one* 4-clock
    // period for every event we're actively reading out.
    //
    // We can probably just integrate this timing into the trigger
    // readout at the TURF since everything's synchronous.
    //
    // NOTE NOTE NOTE NOTE NOTE: THIS NEEDS TO BE RETUNED BASED ON THE SIMULATION
    localparam TERMINATE_DELAY = 3;    
    localparam [3:0] SRL_TERMINATE_DELAY = TERMINATE_DELAY-1;
    reg terminate_seen = 0;
    wire do_terminate;
    // we use terminate_seen to act as a portion of our
    // reset - but that means it needs to be a flag
    reg memclk_reset = 0;
    reg memclk_reset_rereg = 0;
    reg memclk_reset_flag = 0;
    
    SRL16E u_terminate_delay(.D(terminate_seen),
                             .CE(1'b1),
                             .CLK(memclk_i),
                             .A0(SRL_TERMINATE_DELAY[0]),
                             .A1(SRL_TERMINATE_DELAY[1]),
                             .A2(SRL_TERMINATE_DELAY[2]),
                             .A3(SRL_TERMINATE_DELAY[3]),
                             .Q(do_terminate));
    // and then we also need to have a complete delay
    // to signal the other side that we have an event
    // ready to read out.
    localparam COMPLETE_DELAY = 31;
    localparam [4:0] SRL_COMPLETE_DELAY = COMPLETE_DELAY-1;
    wire do_complete;
    SRLC32E u_complete_delay(.D(do_terminate),
                             .CE(1'b1),
                             .CLK(memclk_i),
                             .A(SRL_COMPLETE_DELAY),
                             .Q(do_complete));
                                 
    always @(posedge memclk_i) begin
        memclk_reset <= memclk_rst_i;
        memclk_reset_rereg <= memclk_reset;
        memclk_reset_flag <= memclk_reset && !memclk_reset_rereg;
    
        if (begin_delayed) running <= 1;
        else if (do_terminate) running <= 0;
        
        // Gray coded write buffer.
        if (memclk_reset) write_buffer <= {3{1'b0}};
        else if (do_terminate) begin
            case (write_buffer)
                3'b000: write_buffer <= 3'b001;
                3'b001: write_buffer <= 3'b011;
                3'b011: write_buffer <= 3'b010;
                3'b010: write_buffer <= 3'b110;
                3'b110: write_buffer <= 3'b111;
                3'b111: write_buffer <= 3'b101;
                3'b101: write_buffer <= 3'b100;
                3'b100: write_buffer <= 3'b000;
            endcase
        end        
        // Gray coded complete buffer pointer.
        if (memclk_reset) complete_buffer_pointer <= 3'b000;
        else if (do_complete) begin
            case (complete_buffer_pointer)
                3'b000: complete_buffer_pointer <= 3'b001;
                3'b001: complete_buffer_pointer <= 3'b011;
                3'b011: complete_buffer_pointer <= 3'b010;
                3'b010: complete_buffer_pointer <= 3'b110;
                3'b110: complete_buffer_pointer <= 3'b111;
                3'b111: complete_buffer_pointer <= 3'b101;
                3'b101: complete_buffer_pointer <= 3'b100;
                3'b100: complete_buffer_pointer <= 3'b000;
            endcase                
        end
        
        // terminate_seen going high will kill running after a small number of clocks
        // running going low will end the readout, and everything
        // resets straight away at the next start.
        terminate_seen <= ((write_addr == TERMINATE_VAL) && increment_uaddr) || memclk_reset_flag;

        if (memclk_reset) write_addr <= {5{1'b0}};
        else if (increment_uaddr) write_addr <= write_addr + 1;
        
        if (glob_start) glob_memclk_phase <= GLOB_MEMCLK_PHASE_RESET_VAL;
        else glob_memclk_phase <= glob_memclk_phase + 1;        
    end                                  

    // READOUT PROCESS
    // Even though the readout process is basically stateful
    // it's easier to treat it as something closer to a
    // FIFO, except we don't even worry about the problem of
    // overflow because the TURF protects us from it.
    // So all we need to do is recapture the complete_buffer_pointer
    // and compare it to the read_buffer_pointer, and if they're
    // not equal, we start the readout process.
    //
    // The TURF protects from overflow by keeping its *own*
    // pointers regarding received and sent triggers.
    // This makes this a little less efficient than it could be
    // but whatever.

    // current read buffer
    reg [2:0] read_buffer = {3{1'b0}};
    // write buffer in read domain
    (* CUSTOM_GRAY_DST = IFCLKTYPE *)
    reg [2:0] completed_ifclk_sync = {3{1'b0}};
    // actual version to use
    reg [2:0] completed_buffer = {3{1'b0}};
    // data is available
    reg data_available = 0;
    // from state machine
    wire readout_complete;

    wire [7:0] last_data;
    (* CUSTOM_MC_DST_TAG = "EVBUF_HEADER_SELECT EVBUF_HEADER_DATA EVBUF_DATA" *)
    reg [7:0]  event_data = {8{1'b0}};
    wire       event_valid;
        
    // reset at LOAD_ENABLE_HEADER1, shift at ADDR3_SHIFT_ENABLE
    wire [2:0] active_bram;
    wire [2:0] active_bram_casdomux;
    wire bram_casdomuxen;
    wire [NCHAN-1:0] active_chan;    
    wire [3*NCHAN-1:0] full_casdomux = {
        !active_chan[7] ? 3'b111 : active_bram_casdomux,
        !active_chan[6] ? 3'b111 : active_bram_casdomux,
        !active_chan[5] ? 3'b111 : active_bram_casdomux,
        !active_chan[4] ? 3'b111 : active_bram_casdomux,
        !active_chan[3] ? 3'b111 : active_bram_casdomux,
        !active_chan[2] ? 3'b111 : active_bram_casdomux,
        !active_chan[1] ? 3'b111 : active_bram_casdomux,
        active_bram_casdomux };
    wire [8:0] bram_raddr;

//    wire bram_casdomuxen = (state[1:0] == 2'b00) && dout_data_phase_i;
    // because of our state encoding 
//    wire [1:0] bram_lraddr = state[1:0];
//    // need 7 bits here
//    reg [6:0] bram_uraddr = {7{1'b0}};
//    // I don't know why the v1 module had these backwards, that CANNOT be right
//    wire [9:0] bram_addr = { read_buffer, bram_uraddr, bram_lraddr };
//    // everything is finished. this gets set, then cleared, but it's not a flag.
//    reg readout_complete = 0;
//    // channel complete
//    reg channel_complete = 0;

    wire [31:0] header_data;
    wire header_data_valid;
    wire header_data_read;
    wire select_header_data;
    // sigh. this crap actually goes 5 6 7 4 or 1 2 3 0
    // so I can't just flip things.
    wire [7:0] header_data_remap[3:0];
    assign header_data_remap[0] = header_data[0 +: 8];
    assign header_data_remap[1] = header_data[24 +: 8];
    assign header_data_remap[2] = header_data[16 +: 8];
    assign header_data_remap[3] = header_data[8 +: 8];
    wire [1:0] header_data_addr = bram_raddr[1:0];
    // The headers go in with the trig time first. Because the top bit
    // in the trig time is unused, we set it equal to 1 which allows
    // the DOUT path to automatically know when an event starts because
    // it looks for a 1 in the top bit when it's IDLE.
    //
    // this is aclk, not memclk!
    event_hdr_fifo u_hdr_fifo(.wr_clk(aclk_i),
                              .rd_clk(ifclk_i),
                              .rst( aclk_rst_i ),
                              .din( { 1'b1, trig_time_i, event_no_i } ),
                              .wr_en(trig_valid_i),
                              .full(),
                              .dout( header_data ),
                              .valid( header_data_valid ),
                              .rd_en( header_data_read ));

    (* CUSTOM_CC_DST = "IFCLK" *)
    reg [1:0] loading_fw = {2{1'b0}};
    
    (* CUSTOM_MC_SRC_TAG = "EVBUF_HEADER_SELECT", CUSTOM_MC_MIN = "0", CUSTOM_MC_MAX = "2.0" *)
    reg select_header_data_pipe = 0;
    (* CUSTOM_MC_SRC_TAG = "EVBUF_HEADER_DATA", CUSTOM_MC_MIN = "0", CUSTOM_MC_MAX = "2.0" *)
    reg [7:0] header_data_pipe = {8{1'b0}};
    (* CUSTOM_MC_SRC_TAG = "EVBUF_DATA", CUSTOM_MC_MIN = "0", CUSTOM_MC_MAX = "2.0" *)
    reg [7:0] last_data_pipe = {8{1'b0}};
    reg valid_pipe = 0;
    
    always @(posedge ifclk_i) begin
        loading_fw <= `DLYFF { loading_fw[0], fw_load_i };

        // this is the done buffer pointer clock crossing
        completed_ifclk_sync <= `DLYFF complete_buffer_pointer;
        // and in ifclk. I'm not actually sure I need this?
        // they're actually synchronous?
        completed_buffer <= `DLYFF completed_ifclk_sync;
        // do we need to do something
        data_available <= `DLYFF (completed_buffer != read_buffer);
        // channel change indicator
        // this sets one clock ahead of where it's needed
        // no need to qualify on full
//        if (dout_data_phase_i)
//            channel_complete <= `DLYFF active_bram[2] && bram_uraddr == 7'h7F && bram_lraddr == 2'h2;

        // readout complete isn't a flag, we set it when we see the finish
//        if (dout_data_phase_i) begin
//            if (state == DATA0_ADDR1) `DLYFF readout_complete <= 0;
//            else if (channel_complete && active_chan[7]) `DLYFF readout_complete <= 1;
//        end

        // read buffer will be valid ADDR1_SHIFT_CASDOMUX
        // and then data_available will be valid back in idle
        // VERIFY THIS
        if (ifclk_rst_i) read_buffer <= `DLYFF 3'b000;
        else if (readout_complete) begin
            case (read_buffer)
                3'b000: read_buffer <= `DLYFF 3'b001;
                3'b001: read_buffer <= `DLYFF 3'b011;
                3'b011: read_buffer <= `DLYFF 3'b010;
                3'b010: read_buffer <= `DLYFF 3'b110;
                3'b110: read_buffer <= `DLYFF 3'b111;
                3'b111: read_buffer <= `DLYFF 3'b101;
                3'b101: read_buffer <= `DLYFF 3'b100;
                3'b100: read_buffer <= `DLYFF 3'b000;
            endcase
        end                       
        
        // OK OK OK - I COMPLETELY AND TOTALLY HATE THIS HACK _BUT_
        // I don't want to touch that state machine thing AT ALL.
        // So here's what we're doing:
        // we actually REREGISTER select_header_data with dout_data_phase_i
        // and REREGISTER header_data_remap and last_data the same way.        
        if (dout_data_phase_i) begin
            select_header_data_pipe <= `DLYFF select_header_data;
            header_data_pipe <= `DLYFF header_data_remap[header_data_addr[1:0]];
            last_data_pipe <= `DLYFF last_data;
            valid_pipe <= event_valid;
        end

        if (dout_data_phase_i) begin
            // FIX THIS REVERSE THE ORDER --- I DON'T KNOW WHAT THIS COMMENT MEANT            
            if (select_header_data_pipe) event_data <= `DLYFF header_data_pipe;
            else event_data <= `DLYFF last_data_pipe;
        end
//        if (dout_data_phase_i) begin
//            event_data_valid <= `DLYFF (state == IDLE_HEADER0_ADDR1) ? data_available : !state[3];
//        end

//        if (dout_data_phase_i) begin
//            case (state)
//                IDLE_HEADER0_ADDR1: if (data_available) state <= `DLYFF HEADER1_ADDR2;
//                HEADER1_ADDR2: state <= `DLYFF HEADER2_ADDR3;
//                HEADER2_ADDR3: state <= `DLYFF HEADER3_ADDR0;
//                HEADER3_ADDR0: state <= `DLYFF DATA0_ADDR1;
//                DATA0_ADDR1: state <= `DLYFF DATA1_ADDR2;
//                DATA1_ADDR2: state <= `DLYFF DATA2_ADDR3;
//                DATA2_ADDR3: state <= `DLYFF DATA3_ADDR0;
//                DATA3_ADDR0: state <= `DLYFF DATA0_ADDR1;
//            endcase                
//        end

//          if (ifclk_rst_i) state <= `DLYFF IDLE_HEADER0_ADDR1;
//          else if (dout_data_phase_i || loading_fw[1]) begin
//            case (state)
//                IDLE_HEADER0_ADDR1: if (loading_fw[1]) state <= `DLYFF FW_LOADING_0;
//                                    else if (data_available) state <= `DLYFF HEADER1_ADDR2;
//                HEADER1_ADDR2: state <= `DLYFF HEADER2_ADDR3;
//                HEADER2_ADDR3: state <= `DLYFF HEADER3_ADDR0;
//                HEADER3_ADDR0: state <= `DLYFF DATA1_ADDR2;
//                DATA0_ADDR1: state <= `DLYFF DATA1_ADDR2;
////                DATA0_ADDR1_END: begin
////                                    if (readout_complete) state <= `DLYFF IDLE_HEADER0_ADDR1;
////                                    else state <= `DLYFF DATA1_ADDR2;
////                                 end
////                
//                DATA1_ADDR2: state <= `DLYFF DATA2_ADDR3;
//                DATA2_ADDR3: state <= `DLYFF DATA3_ADDR0;
//                DATA3_ADDR0: state <= `DLYFF DATA0_ADDR1;
//                FW_LOADING_0: if (!loading_fw[1]) state <= `DLYFF IDLE_HEADER0_ADDR1;
//                              else if (fw_wr_i) state <= `DLYFF FW_LOADING_1;
//                FW_LOADING_1: if (!loading_fw[1]) state <= `DLYFF IDLE_HEADER0_ADDR1;
//                              else if (fw_wr_i) state <= `DLYFF FW_LOADING_2;
//                FW_LOADING_2: if (!loading_fw[1]) state <= `DLYFF IDLE_HEADER0_ADDR1;
//                              else if (fw_wr_i) state <= `DLYFF FW_LOADING_3;
//                FW_LOADING_3: if (!loading_fw[1]) state <= `DLYFF IDLE_HEADER0_ADDR1;
//                              else if (fw_wr_i) state <= `DLYFF FW_LOADING_0;
//            endcase
//          end
          // uaddr logic: 
          // if (state == DATA2_ADDR3 && active_bram[2]) or FW_LOADING_3 && fw_wr_i
          // reset at idle always
//          if (state == IDLE_HEADER0_ADDR1)
//                bram_uraddr <= `DLYFF {7{1'b0}};
//          else if ((state == DATA2_ADDR3 && active_bram[2] && dout_data_phase_i) ||
//                   (state == FW_LOADING_3 && fw_wr_i))
//                bram_uraddr <= `DLYFF bram_uraddr + 1;
          // STILL TO DO:
          // --> active bram shift -- DONE
          // --> active channel shift -- DONE
          // --> data muxing -- DONE
          // --> last indicator
          
          // ACTIVE CHANNEL SHIFT
//          if (dout_data_phase_i) begin
//            if (state == IDLE_HEADER0_ADDR1)
//                active_chan <= `DLYFF { {7{1'b0}}, data_available || loading_fw[1] };
//            else if (channel_complete)
//                active_chan <= `DLYFF {active_chan[6:0],1'b0};
//          end
//          // ACTIVE BRAM SHIFT
//          if (dout_data_phase_i) begin
//            if (state == IDLE_HEADER0_ADDR1)
//                active_bram <= `DLYFF 3'b001;
//            else if (state == DATA2_ADDR3)
//                active_bram <= `DLYFF {active_bram[1:0],active_bram[2]};
//          end
    end

    wire [7:0] fw_uaddr;
    uram_event_readout_sm u_sm(.clk_i(ifclk_i),
                               .clk_ce_i(dout_data_phase_i),
                               .data_available_i(data_available),
                               .complete_o(readout_complete),
                               .bram_addr_o(bram_raddr),
                               .bram_en_o(active_bram),
                               .casdomux_o(active_bram_casdomux),
                               .casdomuxen_o(bram_casdomuxen),
                               .channel_en_o(active_chan),
                               .sel_header_o(select_header_data),
                               .header_rd_o(header_data_read),
                               .valid_o(event_valid),
                               .fw_update_uaddr_o(fw_uaddr),
                               .fw_loading_i(loading_fw[1]),
                               .fw_wr_i(fw_wr_i),
                               .fw_mark_i(fw_mark_i),
                               .fwmon_wr_o(fwmon_wr_o));

    // cascades
    wire [35:0] cas_doutb[NCHAN-1:0];
    wire [35:0] cas_dinb[NCHAN-1:0];

    assign cas_dinb[0] = {36{1'b0}};        
    
    wire [23:0] fw_bram_en;    
    generate
        if (DEBUG == "TRUE") begin : ILA
            event_ila u_ila(.clk(ifclk_i),
                            .probe0(header_data),
                            .probe1(event_data),
                            .probe2(select_header_data),
                            .probe3(header_data_valid),
                            .probe4(dout_data_phase_i));
            // sigh, silly debugging.
            // 24 bit enable
            // 8 bit data
            // 1 bit loading
            // 1 bit wr
            // 12 bit addr
            wire [16:0] fw_addr = { fw_uaddr, bram_raddr };
            wire fw_mark = |fw_mark_i;
            (* CUSTOM_MC_DST_TAG = "FW_DATA" *)
            reg [7:0] fw_dat = {8{1'b0}};
            (* CUSTOM_MC_DST_TAG = "FW_VALID" *)
            reg fw_wr = 1'b0;
            always @(posedge ifclk_i) begin : RR
                fw_dat <= fw_dat_i;
                fw_wr <= fw_wr_i; 
            end 
            fwupd_ila u_fwupd_ila(.clk(ifclk_i),
                                  .probe0(fw_bram_en),
                                  .probe1(fw_dat),
                                  .probe2(fw_mark),
                                  .probe3(fw_wr),
                                  .probe4(fw_addr));
        end
    endgenerate           
    generate
        genvar i;
        for (i=0;i<NCHAN;i=i+1) begin : CH
            // calling these LUTx_IDX is archaic but whatever
            localparam LUTA_IDX = 3*i;
            localparam LUTB_IDX = 3*i+1;
            localparam LUTC_IDX = 3*i+2;
            
            localparam [3:0] BRAMA_IN_BANK = (LUTA_IDX < 12) ? LUTA_IDX : (LUTA_IDX - 12);
            localparam BRAMA_BANK = (LUTA_IDX < 12) ? 0 : 1;
            localparam [3:0] BRAMB_IN_BANK = (LUTB_IDX < 12) ? LUTB_IDX : (LUTB_IDX - 12);
            localparam BRAMB_BANK = (LUTB_IDX < 12) ? 0 : 1;
            localparam [3:0] BRAMC_IN_BANK = (LUTC_IDX < 12) ? LUTC_IDX : (LUTC_IDX - 12);
            localparam BRAMC_BANK = (LUTC_IDX < 12) ? 0 : 1;
                       
            // pick off the input data
            wire [71:0] this_channel_data = dat_i[NBIT_IN*i +: NBIT_IN];
            // ALL the input addresses are the same
            wire [7:0] this_bram_uaddr = { write_buffer, write_addr };

            // reading stuff
            wire [2:0] this_bram_casdomux = full_casdomux[3*i +: 3];
            wire [2:0] this_bram_casdomuxen = {3{bram_casdomuxen}};
            wire [2:0] this_bram_rden = active_chan[i] ? active_bram : 3'b000;
            // fwupdate stuff. These can be registered because updates don't
            // happen every clock: they happen at most every 8 clocks. so we
            // have
            // clk  fw_wr    uaddr[6:3] this_bram_wren
            // 0    1        11         0
            // 1    0        12         0
            // 2    0        0          0
            // 3..7 0        0          1
            // 8    1        0          1
            // this is simple now
            reg [2:0] this_bram_wren = {3{1'b0}};
            assign fw_bram_en[3*i +: 3] = this_bram_wren;
// OLD STUFF                                    
//            (* KEEP = "TRUE", DONT_TOUCH = "TRUE", CUSTOM_BRAM_LUT_IDX = LUTA_IDX *)
//            LUT4 #(.INIT(16'h8000)) u_brA_dec(.I0(fw_uaddr[3]),
//                                              .I1(fw_uaddr[4]),
//                                              .I2(fw_uaddr[5]),
//                                              .I3(fw_uaddr[6]),
//                                              .O(this_bram_wren_decode[0]));
//            (* KEEP = "TRUE", DONT_TOUCH = "TRUE", CUSTOM_BRAM_LUT_IDX = LUTB_IDX *)
//            LUT4 #(.INIT(16'h8000)) u_brB_dec(.I0(fw_uaddr[3]),
//                                              .I1(fw_uaddr[4]),
//                                              .I2(fw_uaddr[5]),
//                                              .I3(fw_uaddr[6]),
//                                              .O(this_bram_wren_decode[1]));
//            (* KEEP = "TRUE", DONT_TOUCH = "TRUE", CUSTOM_BRAM_LUT_IDX = LUTC_IDX *)
//            LUT4 #(.INIT(16'h8000)) u_brC_dec(.I0(fw_uaddr[3]),
//                                              .I1(fw_uaddr[4]),
//                                              .I2(fw_uaddr[5]),
//                                              .I3(fw_uaddr[6]),
//                                              .O(this_bram_wren_decode[2]));
            always @(posedge ifclk_i) begin : WLGC
                this_bram_wren[0] <= (fw_uaddr[6:3] == BRAMA_IN_BANK) && (fw_uaddr[7] == BRAMA_BANK);
                this_bram_wren[1] <= (fw_uaddr[6:3] == BRAMB_IN_BANK) && (fw_uaddr[7] == BRAMB_BANK);
                this_bram_wren[2] <= (fw_uaddr[6:3] == BRAMC_IN_BANK) && (fw_uaddr[7] == BRAMC_BANK);
            end
                                              
            wire [2:0] this_bram_en = (loading_fw[1]) ? this_bram_wren : this_bram_rden;
            wire this_bram_regce = !dout_data_phase_i;
            wire [11:0] this_bram_raddr = (loading_fw[1]) ? { fw_uaddr[2:0], bram_raddr} : { read_buffer, bram_raddr };
            wire [7:0] this_bram_dat_o;
            wire [7:0] this_bram_upd_dat = {8{1'b0}};
            wire this_bram_upd_wr = 1'b0;
            wire [2:0] this_bram_upd_casdimux = {3{1'b0}};

            if (i == NCHAN-1) begin : LAST
                assign last_data = this_bram_dat_o;
            end
            if (i != 0) begin : CNF
                assign cas_dinb[i] = cas_doutb[i-1];
            end
            localparam CHANNEL_ORDER = ( (i==0) ? "FIRST" : ( (i==NCHAN-1) ? "LAST" : "MIDDLE"));
            // because they're ALL operating with no delay, the run delay can just be zero
            // next_bram_uaddr_o is then ignored.
            uram_event_chbuffer #(.RUN_DELAY(0),
                                  .CHANNEL_ORDER(CHANNEL_ORDER),
                                  .CHANNEL_INDEX(i))
                u_chbuffer(.memclk_i(memclk_i),
                           .channel_run_i(running),
                           .bram_uaddr_i(this_bram_uaddr),
//                           .next_bram_uaddr_o(this_next_bram_uaddr),
                           .dat_i(this_channel_data),
                           .ifclk_i( ifclk_i ),
                           .bram_regce_i(this_bram_regce),
                           .bram_casdomux_i(this_bram_casdomux),
                           .bram_casdomuxen_i(this_bram_casdomuxen),
                           .bram_en_i(this_bram_en),
                           .bram_raddr_i(this_bram_raddr),
                           .dat_o(this_bram_dat_o),
                           .bram_upd_dat_i( fw_dat_i ),
                           .bram_upd_wr_i( {3{fw_wr_i}} ),
                           .bram_upd_casdimux_i( {3{1'b0}} ),
                           .cascade_in_i( cas_dinb[i] ),
                           .cascade_out_o(cas_doutb[i] ));
        end
    endgenerate        
    
    assign dout_data_o = event_data;
    assign dout_data_valid_o= valid_pipe;
    // screw this for now
    assign dout_data_last_o = 1'b0;
        
endmodule
