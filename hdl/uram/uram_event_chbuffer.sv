`timescale 1ns / 1ps
// OK - this is the SINGLE CHANNEL version
// of the event readout stage. The generate
// loop was getting too complicated and
// there's still the readout logic to handle.
//
// SAMPLE_ORDER allows you to define how the nybbles are captured.
// it labels the incoming samples as
// sample 0: CBA
// sample 1: FED
// if we capture this FEDCBA, then the readout data looks like
// BA, DC, FE
// D0  D1  D2
// which means
// S[0] = D0 + ((D1) << 8) & 0xF00)
// S[1] = ((D1>>4) & 0xF) + (D2 << 4)
// we could also do (e.g.) FCEDBA, which would give us
// BA, ED, FC which would allow for converting by
// D0  D1  D2
// S[0] = D0 + ((D2 << 8) & 0xF00)
// S[1] = D1 + ((D2 << 4) & 0xF00)
// obviously any other option works too
module uram_event_chbuffer #(parameter RUN_DELAY=0,
                             parameter CHANNEL_ORDER="FIRST",
                             parameter CR_CROSS="FALSE",
                             parameter CHANNEL_INDEX = 0,
                             parameter SAMPLE_ORDER="FEDCBA")(
        // write side. this is 1024x96 = 98,304 bits = 8192 x 12 samples
        // = 8 buf x 1024 samples/buf x 12 bits/sample
        input memclk_i,
        input channel_run_i,
        input [7:0] bram_uaddr_i,
        output [7:0] next_bram_uaddr_o,
        input [71:0] dat_i,
        // Read side. Because we now are handling this 8 bits at a time,
        // we handle the individual BRAM and channel addressing one-hot.
        input ifclk_i,  
        // these are the BRAM cascade enables
        input [2:0] bram_casdomux_i,
        input [2:0] bram_casdomuxen_i,
        // this determines if we're actually reading from a BRAM
        input [2:0] bram_en_i,
        // register output enable for the last BRAM
        input       bram_regce_i,
        // because we've divided out the 3 above with the one-hot,
        // the buffer is 3x32768 = 3x8 bits x 4096 addresses
        // = 8 buffers x 3 BRAMs x 512 addresses x 8 bits
        // 8 buffers * 512 addresses/buffer = 2^12 addresses
        input [11:0] bram_raddr_i,        
        // This is the 8 bit output of the top BRAM in one channel
        output [7:0] dat_o,
        // THIS IS THE SLEAZEBALL STUFF
        // this is the data *input* for the update path
        input [7:0] bram_upd_dat_i,
        // actually write the data
        input [2:0] bram_upd_wr_i,
        // and the casdimux inputs
        input [2:0] bram_upd_casdimux_i,
        // BRAM CASCADE STUFF
        input [35:0] cascade_in_i,
        output [35:0] cascade_out_o
    );

    localparam IDX_A = 3*CHANNEL_INDEX + 0;
    localparam IDX_B = 3*CHANNEL_INDEX + 1;
    localparam IDX_C = 3*CHANNEL_INDEX + 2;

    // this is how we make the output parameterizable
    // 8'h41 is 'A'
    localparam S0 = SAMPLE_ORDER[7:0] - 8'h41;
    localparam S1 = SAMPLE_ORDER[15:8] - 8'h41;
    localparam S2 = SAMPLE_ORDER[23:16] - 8'h41;
    localparam S3 = SAMPLE_ORDER[31:24] - 8'h41;
    localparam S4 = SAMPLE_ORDER[39:32] - 8'h41;
    localparam S5 = SAMPLE_ORDER[47:40] - 8'h41;
    function [23:0] map_output;
        input [23:0] in_data;
        input [7:0] idx0;
        input [7:0] idx1;
        input [7:0] idx2;
        input [7:0] idx3;
        input [7:0] idx4;
        input [7:0] idx5;
        begin
            map_output[3:0] = in_data[4*idx0 +: 4];
            map_output[7:4] = in_data[4*idx1 +: 4];
            map_output[11:8] = in_data[4*idx2 +: 4];
            map_output[15:12] = in_data[4*idx3 +: 4];
            map_output[19:16] = in_data[4*idx4 +: 4];
            map_output[23:20] = in_data[4*idx5 +: 4];
        end
    endfunction        

    localparam RESET_LADDR_DELAY = 1;
    // NOTE:
    // The Memory Resources Guide on the cascade feature is just terrible.
    // There are 3 cascade select control pins on a block RAM
    // CASDOMUX: if 1, DOUT = CASDIN, if 0, DOUT = DO_REG (if used) or BRAM out (if not)
    // CASOREGIMUX: if 1, input to DO_REG = CASDIN, if 0, input to DO_REG = BRAM out
    // CASDIMUX: if 1, data input = CASDIN, if 0, data input = DIN
    //
    // All of these are dynamic controls. Only DO_REG is an attribute.
    //
    // CASDIMUX is not shown in any diagram anywhere in the document, but it's
    // in the text.
    //
    // We use the data in cascade to use the block RAM as a large data buffer that
    // the CPU can extract update firmware from using JTAG. Hopefully!
    // Not worrying about that right now!!
    
    // The event buffer readout is sequenced such that for writes,
    // we generate the low 2 bits ourselves and get the top bits
    // from a single bit of control logic functionally running at 1/4th
    // the clock rate.
    
    // This means we have phase tracking registers, which are
    // sequenced off of channel_run_i (although if this ends up being
    // an issue there's other things that can be done).
    
    // Phase track registers, one-hot encoded
    localparam MEMCLK_PHASE_RESET_VAL = 4'b1000;

    reg [3:0] memclk_phase = {4{1'b0}};
    // don't toggle the timer phase when it happens in phase 3
    // the pulses happen in (no pulse), phase 0, phase 2, phase 3
    // so with a counter, you use !bit[0], with a one-hot you use memclk_phase[3]
    wire uram_timer_toggle_phase = !memclk_phase[3];
    // select the muxed value. we need the muxed vals in phase 1 and 2
    // so use_muxed_val needs to be high in 0 and 1
    // meaning use_mux_val <= (phase[3] || phase[0])
    reg use_muxed_val = 0;    
    // Buffer A holding register.
    reg [31:0] bufA_in = {32{1'b0}};
    // Buffer B holding register
    reg [31:0] bufB_in = {32{1'b0}};
    // Buffer C holding register
    reg [31:0] bufC_in = {32{1'b0}};
    
    // Buffer A byte write enables
    wire [3:0] bufA_bwe = {4{!memclk_phase[2]}};
    // Buffer B byte write enables
    wire [3:0] bufB_bwe = {{2{!memclk_phase[1]}},
                           {2{!memclk_phase[2]}}};
    // Buffer C byte write enables                           
    wire [3:0] bufC_bwe = {{3{!memclk_phase[0]}},
                              !memclk_phase[1]};
    // Buffer A and B don't use the ADDREN functionality
    // because they both keep static addresses in phase 2,
    // but the address doesn't change from phase 1 to phase 2
    // Buffer C does use it, however.
    wire bufC_addren = !memclk_phase[1];

    // this is the delayed channel_run_i
    wire this_run;
    // and then this turns on the actual write
    reg [1:0] this_enable = {2{1'b0}};
    // this is the flag determined from channel_run_i from the timer
    wire start;
    // this tells us to reset the laddr count
    wire reset_laddr;
    // this is the flag from the timer telling us to capture upper addr
    wire uaddr_capture;
    
    // this is our lower address bits
    reg [1:0] bram_laddr = {2{1'b0}};
    // these are our upper address bits
    reg [7:0] bram_uaddr = {8{1'b0}};
    
    // the address is always 14 bits
    // our write side is 36 bits so addr is [14:5] meaning 5 zeros on the bottom
    wire [14:0] this_bram_addr_A = { bram_uaddr, bram_laddr, {5{1'b0}} };
    // our read side is 9 bits so addr is [14:3] meaning 3 zeros on the bottom
    wire [14:0] this_bram_addr_B = { bram_raddr_i, {3{1'b0}} };
    // handle variable starts
    // might be able to do this smarter
    generate
        if (RUN_DELAY == 0) begin : NRD
            assign this_run = channel_run_i;
        end else if (RUN_DELAY < 17) begin : SRL16RD
            localparam [3:0] SRL_RUN_DLY = RUN_DELAY - 2;
            wire run_srl_delay;
            reg local_run = 0;
            SRL16E u_rundly(.D(channel_run_i),
                            .CE(1'b1),
                            .CLK(memclk_i),
                            .A0(SRL_RUN_DLY[0]),
                            .A1(SRL_RUN_DLY[1]),
                            .A2(SRL_RUN_DLY[2]),
                            .A3(SRL_RUN_DLY[3]),
                            .Q(run_srl_delay));
            always @(posedge memclk_i) local_run <= run_srl_delay;
            assign this_run = local_run;                                
        end else begin : SRL32RD
            localparam [4:0] SRL_RUN_DLY = RUN_DELAY - 2;
            wire run_srl_delay;
            reg local_run = 0;
            SRLC32E u_rundly(.D(channel_run_i),
                             .CE(1'b1),
                             .CLK(memclk_i),
                             .A(SRL_RUN_DLY),
                             .Q(run_srl_delay));
            always @(posedge memclk_i) local_run <= run_srl_delay;
            assign this_run = local_run;                                
        end
        if (RESET_LADDR_DELAY == 0) begin : NLD
            assign reset_laddr = start;
        end else if (RESET_LADDR_DELAY == 1) begin : RLD
            reg start_rereg = 0;
            always @(posedge memclk_i) begin : RLDL
                start_rereg <= start;
            end
            assign reset_laddr = start_rereg;
        end else begin : SRLLD
            localparam [3:0] RESET_LADDR_SRLVAL = RESET_LADDR_DELAY-1;
                localparam [3:0] SRL_LADDR_DELAY_VAL = RESET_LADDR_DELAY - 1;
                SRL16E u_delay_reset(.D(start),
                                     .CE(1'b1),
                                     .CLK(memclk_i),
                                     .A0(SRL_LADDR_DELAY_VAL[0]),
                                     .A1(SRL_LADDR_DELAY_VAL[1]),
                                     .A2(SRL_LADDR_DELAY_VAL[2]),
                                     .A3(SRL_LADDR_DELAY_VAL[3]),
                                     .Q(reset_laddr));            
        end
    endgenerate        

    // timer
    uram_event_timer u_timer(.memclk_i(memclk_i),
                             .memclk_phase_i(uram_timer_toggle_phase),
                             .running_i(this_run),
                             .start_o(start),
                             .capture_o(uaddr_capture));

    // WRITE-IN IS ALWAYS IN MEMCLK
    // dat_i always has 3 chunks
    wire [23:0] chunk0 = map_output(dat_i[0 +: 24], S0, S1, S2, S3, S4, S5);
    wire [23:0] chunk1 = map_output(dat_i[24 +: 24], S0, S1, S2, S3, S4, S5);
    wire [23:0] chunk2 = map_output(dat_i[48 +: 24], S0, S1, S2, S3, S4, S5);
    always @(posedge memclk_i) begin
        this_enable <= { this_enable[0], this_run };
    
        if (start) memclk_phase <= MEMCLK_PHASE_RESET_VAL;
        else memclk_phase <= {memclk_phase[2:0], memclk_phase[3]};
        
        if (reset_laddr)
            bram_laddr <= {2{1'b0}};
        else if (!memclk_phase[1])
            bram_laddr <= bram_laddr + 1;

        if (uaddr_capture) bram_uaddr <= bram_uaddr_i;
        
        use_muxed_val <= (memclk_phase[3] || memclk_phase[0]);
        
        // don't capture A0/1/2 in memclk_phase[2] to avoid
        // needing to increment address
        if (!memclk_phase[2])
            bufA_in[0 +: 24] <= chunk0;
        // A3/B0/B1 mux their input data
        if (use_muxed_val) begin
            bufA_in[24 +: 8] <= chunk2[0 +: 8];
            bufB_in[0 +: 16] <= chunk2[8 +: 16];            
        end else begin
            bufA_in[24 +: 8] <= chunk1[0 +: 8];
            bufB_in[0 +: 16] <= chunk1[8 +: 16];                        
        end
        // B2/B3/C0 do not
        bufB_in[16 +: 16] <= chunk2[0 +: 16];
        bufC_in[0 +: 8] <= chunk2[16 +: 8];
        // C1/C2/C3 also mux
        if (use_muxed_val)
            bufC_in[8 +: 24] <= chunk1;
        else
            bufC_in[8 +: 24] <= chunk0;
    end

    // ACTUAL BRAMS ARE HERE
    // There are no A-port cascades at all.
    // the B port cascades go from A->B->C
    // it's really 36-bit, just tack on the parity which is unused anyway
    wire [35:0] bramA_to_B;
    wire [35:0] bramB_to_C;
    
    wire [31:0] bram_dout;
    
    // because we're now in standard data cascade mode, *ALL* of the RAMs use their output regs
    (* CUSTOM_BRAM_IDX = IDX_A *)
    RAMB36E2 #(.CASCADE_ORDER_A("NONE"),
               .CASCADE_ORDER_B(CHANNEL_ORDER == "FIRST" ? "FIRST" : "MIDDLE"),
               .CLOCK_DOMAINS("INDEPENDENT"),
               // DOA is unimportant, so disable it
               .DOA_REG(1'b0),
               .DOB_REG(1'b1),
               // bram A port A doesn't need ADDREN
               .ENADDRENA("FALSE"),
               // port Bs never need ADDREN
               .ENADDRENB("FALSE"),
               // don't bother with inits
               // don't bother with RDADDRCHANGE
               .READ_WIDTH_A(36),
               .WRITE_WIDTH_A(36),
               .READ_WIDTH_B(9),
               .WRITE_WIDTH_B(9),
               // don't bother with RSTREG_PRIORITY_A/B
               // SLEEP is awkward so we won't use it at first but who knows
               // don't bother with SRVAL_A/B or WRITE_MODE_A/B
               .SLEEP_ASYNC("FALSE"))
        u_bramA( .CLKARDCLK( memclk_i ),
                 .DINADIN( bufA_in ),
                 .DINPADINP( {4{1'b0}} ),
                 .ADDRARDADDR( this_bram_addr_A ),
                 .WEA( bufA_bwe ),
                 .ENARDEN( this_enable[1] ),
                 .RSTRAMARSTRAM(1'b0),
                 
                 .CLKBWRCLK( ifclk_i ),
                 .DINBDIN( { {24{1'b0}}, bram_upd_dat_i } ),
                 .ADDRBWRADDR( this_bram_addr_B ),
                 .WEBWE( { {7{1'b0}}, bram_upd_wr_i[0] } ),
                 .ENBWREN( bram_en_i[0] ),
                 .REGCEB( bram_regce_i ),
                 .RSTRAMB( 1'b0 ),
                 
                 .CASOREGIMUXB(1'b0),
                 .CASOREGIMUXEN_B(1'b0),
                 .CASDOMUXB( bram_casdomux_i[0] ),
                 .CASDOMUXEN_B( bram_casdomuxen_i[0] ),
                 
                 .CASDINB( cascade_in_i[31:0] ),
                 .CASDINPB( cascade_in_i[35:32] ),
                 .CASDOUTB( bramA_to_B[31:0] ),
                 .CASDOUTPB( bramA_to_B[35:32] ));

    (* CUSTOM_BRAM_IDX = IDX_B *)
    RAMB36E2 #(.CASCADE_ORDER_A("NONE"),
               .CASCADE_ORDER_B("MIDDLE"),
               .CLOCK_DOMAINS("INDEPENDENT"),
               // DOA is unimportant, so disable it
               .DOA_REG(1'b0),
               // all BRAMs use output regs
               .DOB_REG(1'b1),
               // bram B port A doesn't need ADDREN
               .ENADDRENA("FALSE"),
               // port Bs never need ADDREN
               .ENADDRENB("FALSE"),
               // don't bother with inits
               // don't bother with RDADDRCHANGE
               .READ_WIDTH_A(36),
               .WRITE_WIDTH_A(36),
               .READ_WIDTH_B(9),
               .WRITE_WIDTH_B(9),
               // don't bother with RSTREG_PRIORITY_A/B
               // SLEEP is awkward so we won't use it at first but who knows
               // don't bother with SRVAL_A/B or WRITE_MODE_A/B
               .SLEEP_ASYNC("FALSE"))
        u_bramB( .CLKARDCLK( memclk_i ),
                 .DINADIN( bufB_in ),
                 .DINPADINP( {4{1'b0}} ),
                 .ADDRARDADDR( this_bram_addr_A ),
                 .WEA( bufB_bwe ),
                 .ENARDEN( this_enable[1] ),
                 .RSTRAMARSTRAM(1'b0),
                 .DINBDIN( { {24{1'b0}}, bram_upd_dat_i } ),
                 
                 .CLKBWRCLK( ifclk_i ),
                 .ADDRBWRADDR( this_bram_addr_B ),
                 .WEBWE( { {7{1'b0}}, bram_upd_wr_i[1] } ),
                 .ENBWREN( bram_en_i[1] ),
                 .REGCEB( bram_regce_i ),
                 .RSTRAMB( 1'b0 ),
                 
                 .CASOREGIMUXB(1'b0),
                 .CASOREGIMUXEN_B(1'b0),
                 .CASDOMUXB( bram_casdomux_i[1] ),
                 .CASDOMUXEN_B( bram_casdomuxen_i[1] ),
                 
                 .CASDINB( bramA_to_B[31:0] ),
                 .CASDINPB( bramA_to_B[35:32] ),
                 .CASDOUTB( bramB_to_C[31:0] ),
                 .CASDOUTPB( bramB_to_C[35:32] ));
    // son of a bitch, this doesn't work. it ALWAYS needs to be a straight cascade
    // whatever, it managed to make it work.
    // I'll change the uram_event_buffer to directly register the output anyway.
//    wire casoregimuxb_bramC = (CHANNEL_ORDER == "LAST") ? bram_casdomux_i[2] : 1'b0;
//    wire casoregimuxenb_bramC = (CHANNEL_ORDER == "LAST") ? bram_casdomuxen_i[2] : 1'b0;
//    wire casdomuxb_bramC = (CHANNEL_ORDER == "LAST") ? 1'b0 : bram_casdomux_i[2];
//    wire casdomuxenb_bramC = (CHANNEL_ORDER == "LAS") ? 1'b0 : bram_casdomuxen_i[2];
    wire casoregimuxb_bramC = 1'b0;
    wire casoregimuxenb_bramC = 1'b0;
    wire casdomuxb_bramC = bram_casdomux_i[2];
    wire casdomuxenb_bramC = bram_casdomuxen_i[2];
        
    (* CUSTOM_BRAM_IDX = IDX_C *)
    RAMB36E2 #(.CASCADE_ORDER_A("NONE"),
               .CASCADE_ORDER_B(CHANNEL_ORDER == "LAST" ? "LAST" : "MIDDLE"),
               .CLOCK_DOMAINS("INDEPENDENT"),
               // DOA is unimportant, so disable it
               .DOA_REG(1'b0),
               // all BRAMs use output regs
               .DOB_REG(1'b1),
               // bram C port A needs ADDREN
               .ENADDRENA("TRUE"),
               // port Bs never need ADDREN
               .ENADDRENB("FALSE"),
               // don't bother with inits
               // don't bother with RDADDRCHANGE
               .READ_WIDTH_A(36),
               .WRITE_WIDTH_A(36),
               .READ_WIDTH_B(9),
               .WRITE_WIDTH_B(9),
               // don't bother with RSTREG_PRIORITY_A/B
               // SLEEP is awkward so we won't use it at first but who knows
               // don't bother with SRVAL_A/B or WRITE_MODE_A/B
               .SLEEP_ASYNC("FALSE"))
        u_bramC( .CLKARDCLK( memclk_i ),
                 .DINADIN( bufC_in ),
                 .DINPADINP( {4{1'b0}} ),
                 .ADDRARDADDR( this_bram_addr_A ),
                 .ADDRENA( bufC_addren ),
                 .WEA( bufC_bwe ),
                 .ENARDEN( this_enable[1] ),
                 .RSTRAMARSTRAM(1'b0),
                 .DINBDIN( { {24{1'b0}}, bram_upd_dat_i } ),                 
                 .CLKBWRCLK( ifclk_i ),
                 .DOUTBDOUT( bram_dout ),
                 .ADDRBWRADDR( this_bram_addr_B ),
                 .WEBWE( { {7{1'b0}}, bram_upd_wr_i[2] } ),

                 .ENBWREN( bram_en_i[2] ),
                 .REGCEB( bram_regce_i ),
                 .RSTRAMB( 1'b0 ),

                 .CASOREGIMUXB(casoregimuxb_bramC),
                 .CASOREGIMUXEN_B(casoregimuxenb_bramC),
                 .CASDOMUXB( casdomuxb_bramC ),
                 .CASDOMUXEN_B( casdomuxenb_bramC ),            
                 
                 .CASDINB( bramB_to_C[31:0] ),
                 .CASDINPB( bramB_to_C[35:32] ),
                 .CASDOUTB( cascade_out_o[31:0] ),
                 .CASDOUTPB( cascade_out_o[35:32] ));

    assign dat_o = bram_dout[7:0];            

    assign next_bram_uaddr_o = bram_uaddr;
endmodule
