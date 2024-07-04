`timescale 1ns / 1ps
`include "interfaces.vh"
// URAM-to-Event buffer.
// LOL at calling this v2, since v1 was never finished
module uram_event_buffer_v2 #(parameter NCHAN = 8,
                           parameter NBIT_IN = 72)(
        input memclk_i,
        input memclk_phase_i,
        input memclk_rst_i,
        input ifclk_i,
        input ifclk_rst_i,
        // This is no longer a "dat_valid",
        // it's a "readout begin" flag. It begins
        // BEFORE the data becomes valid.
        input dat_readout_i,
        input [NBIT_IN*NCHAN-1:0] dat_i
    );
    
    // Everything we do is conditioned on the memclk phase - 
    // we basically operate in lockstep with the pueo_uram module.

    // there is ONE global write buffer address + buffer address
    reg [6:0] global_write_addr = {7{1'b0}};
    // we reregister it to distribute it because everyone registers
    // their inputs so they're a clock behind
    (* SHREG_EXTRACT = "NO" *)
    reg [6:0] write_addr_rereg = {7{1'b0}};
    // the write buffer is totally static during readout so it
    // doesn't need a duplicate
    reg [2:0] write_buffer = {3{1'b0}};

    // this comes from pueo_uram and is terminated by us
    // We can probably time pueo_uram's assertion so that
    // this gets a multicycle path and recaptured locally at phase
    // we *definitely* can time the deassertion
    reg writing_in = 0;

    // we'll explicitly buffer memclk_phase_i here
    // e.g.
    // memclk_phase memclk_phase_buf    next_is_middle_phase   middle_phase
    // 0 3            0100                0                      0
    // 1 0           1000                1                      0
    // 0 1           0001                1                      1
    // 0 2           0010                0                      1
    // 0 3           0100                0                      0
    // 1 0           1000                1                      0
    reg [3:0] memclk_phase_buf = {4{1'b0}};
    wire module_memclk_phase = memclk_phase_buf[3];
    
    always @(posedge memclk_i) begin
        memclk_phase_buf <= { memclk_phase_buf[2:0], memclk_phase_i };
    end
    
    // note: I *do not think* that I can cascade all these guys together
    // I think I should just split 'em up into groups of 3 and
    // route the cascade myself. But we'll see!
    
    generate
        genvar i;
        for (i=0;i<NCHAN;i=i+1) begin : CH
            // get *our* input data
            wire [71:0] this_in = dat_i[NBIT_IN*i +: NBIT_IN];

            //////////////////////////////////////////////////////////////////
            //                      EVENT WRITE LOGIC                       //
            //////////////////////////////////////////////////////////////////

            // global enable, propagated from writing_in
            reg write_ram_enable = 0;
            
            // each channel has 3 32-bit buffers
            reg [31:0] bufA = {32{1'b0}};
            reg [31:0] bufB = {32{1'b0}};
            reg [31:0] bufC = {32{1'b0}};
            // local phase buffer
            reg [3:0] local_phase_reg = {4{1'b0}};
            // phase 1 or 2
            reg middle_phase = 0;
            // actually map to the correct values
            wire [3:0] local_phase = { local_phase_reg[2:0], local_phase_reg[3] };
            
            // write enables
            wire [3:0] bufA_wren;
            wire [3:0] bufB_wren;
            wire [3:0] bufC_wren;            
            // address enables
            // always
            wire bufA_addren = 1'b1;
            // not phase 2
            wire bufB_addren = ~local_phase[2];
            // not phase 1
            wire bufC_addren = ~local_phase[1];
            
            // bufA writes except for phase 2
            assign bufA_wren = ~{4{local_phase[2]}};
            // bufB0/1 are not phase 2, bufB2/3 are not phase 1
            assign bufB_wren = { {2{~local_phase[1]}}, {2{~local_phase[2]}} };
            // bufC0 is not phase 1, bufC3/2/1 are not phase 0
            assign bufC_wren = { {3{~local_phase[0]}}, ~local_phase[1] };
                                               
            always @(posedge memclk_i) begin
                // note, by doing it this way we 'start running' a cycle early
                // and write in silliness which is immediately overwritten
                // WHOOP DE DOO
                // writing_in -> ram_enable is a multicycle path
                if (local_phase[2]) write_ram_enable <= writing_in;
            
                local_phase_reg <= { local_phase_reg[2:0], module_memclk_phase };
                middle_phase <= local_phase[0] || local_phase[1];
                
                // bufA 0, 1, 2 are direct buffered but don't update in phase 3
                if (!local_phase[3]) bufA[0 +: 24] <= this_in[0 +: 24];
                // bufA 3 toggles in middle phase between samples 2 and 4's primaries
                if (middle_phase) bufA[24 +: 8] <= this_in[24 +: 8];
                else bufA[24 +: 8] <= this_in[48 +: 8];
                
                // bufB 0, 1 toggle between &23/3 and &45/5
                if (middle_phase) bufB[0 +: 16] <= this_in[56 +: 16];
                else bufB[0 +: 16] <= this_in[32 +: 16];
                
                // bufB 2/3 are their happy little selves taking 4&45
                bufB[16 +: 16] <= this_in[48 +: 16];
                
                // bufC0 is also its happy self with the top byte
                bufC[0 +: 8] <= this_in[64 +: 8];
                // and bufC1/2/3 all toggle
                if (middle_phase) bufC[8 +: 24] <= this_in[24 +: 24];
                else bufC[8 +: 24] <= this_in[0 +: 24];
            end            

            //////////////////////////////////////////////////////////////////
            //                      EVENT READ LOGIC                        //
            //////////////////////////////////////////////////////////////////


        end    
    endgenerate

//                    RAMB36E2
//                                #(.CASCADE_ORDER_A("NONE"),
//                               .CASCADE_ORDER_B("FIRST"),
//                               .CLOCK_DOMAINS("COMMON"),
//                               .SIM_COLLISION_CHECK("ALL"),
//                               .DOA_REG(1'b0),
//                               .DOB_REG(1'b1),
//                               .ENADDRENA("FALSE"),
//                               .ENADDRENB("TRUE"),
//                               .EN_ECC_PIPE("FALSE"),
//                               .EN_ECC_READ("FALSE"),
//                               .EN_ECC_WRITE("FALSE"),
//                               .RDADDRCHANGEB("TRUE"),
//                               .READ_WIDTH_A(9),
//                               .READ_WIDTH_B(9),
//                               .WRITE_WIDTH_A(9),
//                               .WRITE_WIDTH_B(9),
//                               .RSTREG_PRIORITY_A("RSTREG"),
//                               .RSTREG_PRIORITY_B("RSTREG"),
//                               .SLEEP_ASYNC("FALSE"))
//                               u_bufC(.CASDOUTB(bramC_to_B),
//                                      .CASDOUTPB(brampC_to_B),
//                                      // RIGHT NOW I'm not going to worry
//                                      // about the upgrade RAM possibility.
//                                      // That needs to happen sooner rather
//                                      // than later but WE'LL SEE
//                                      .ADDRBWRADDR( {write_buffer,write_address,3'b000 } ),
//                                      // ENARDEN enables power save, so that's low the majority
//                                      // of the time. We don't qualify it with memclk_phase_i
//                                      // to avoid logic. It doesn't really matter, it's a tiny
//                                      // amount of extra power.
//                                      .ENARDEN(running),
//                                      .WEA({3'b000,!memclk_phase_i}),
//                                      .DINADIN( { {24{1'b0}}, holdA } ),
//                                      .DINPADINP( {4{1'b0}} ),
//                                      // this becomes something later
//                                      .DINBDIN(),
//                                      .DINPBDINP(),
//                                      // DOUT is unconnected here because
//                                      // it's ONLY cascaded
//                                      .REGCEB()); 
    
    
endmodule
