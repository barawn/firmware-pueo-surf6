`timescale 1ns / 1ps
// THIS HAS TO BE MODIFIED FOR ANYTHING MORE THAN 48 BEAMS
// NO METADATA YET FRIGGIN DEAL WITH IT
`include "interfaces.vh"
`include "dsp_macros.vh"
// NOTE NOTE NOTE - THIS HAS TO BE RUNNING OUTSIDE OF TCLK
// TO MAINTAIN PHASE
//
//
// TOTAL LATENCY:
// aclk:
// 0 trigger high on input
// 1 trigger high in C
// 2 trigger high at register
// 3 trigger high at trigger_registered
// 4 trigger_high at trigger_stretch
// 5-7: trigger high at trigger_ifclk
// + 37 clock latency
// = 42-44 ACLK clocks = 14-15 addresses
module surf_trig_gen #(parameter NBEAMS=48,
                       parameter ACLKTYPE = "NONE")(
        input aclk,
        // aclk phase = 1 indicates first phase of 3-clock cycle
        input aclk_phase_i,
        input [NBEAMS-1:0] trig_i,
        // mask is written stupidly: 30 bits in one register
        // and 18 bits in the other because we're using the A/B registers
        // in a 48-bit pair.
        input [NBEAMS-1:0] mask_i,
        input [1:0] mask_wr_i,
        input mask_update_i,
        input gen_rst_i,
        input ifclk,
        input runrst_i,
        input runstop_i,
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( trig_ , 32 )        
    );
    // can send 1 trigger per 24 clocks
    localparam TRIG_CLOCK_RATE = 24;
    // imagine a 4 clock cycle
    // clk  trigger     trigger_registered      trig_holdoff    trig_holdoff_complete   shreg
    // 0    0           0                       0               0                       000
    // 1    1           0                       0               0                       000
    // 2    X           1                       1               0                       000
    // 3    X           0                       1               0                       001
    // 4    X           0                       1               1                       010
    // 5    1           0                       0               0                       100
    // 6    X           1                       1               0                       000
    // this would need a shreg address of 0
    // so we have to subtract 4
    localparam [4:0] HOLDOFF_ADDR = TRIG_CLOCK_RATE-4;
    
    reg [NBEAMS-1:0] trigin_rereg = {NBEAMS{1'b0}};
    
    // first step is to do the reductive-or
    // this is best done in a DSP.
    wire [47:0] dsp_mask_in = (NBEAMS < 48) ? { {(NBEAMS-48){1'b0}}, mask_i } : mask_i;
    wire [47:0] dsp_trig_in = (NBEAMS < 48) ? { {(NBEAMS-48){1'b0}}, trigin_rereg } : trigin_rereg;
    
    (* CUSTOM_CC_DST = ACLKTYPE *)
    reg [1:0] trig_gen_rst = {2{1'b0}};
    
    wire not_trigger;
    reg trigger = 0;
    // flop registering the patterndetect output - generates a flag due to holdoff
    reg trigger_registered = 0;
    // trigger_registered through the shreg
    wire trig_holdoff_dly;
    // registered shreg output
    reg trig_holdoff_complete = 0;
    // prevent new triggers
    reg trig_holdoff = 0;
    
    SRLC32E u_holdoff_dly(.D(trigger_registered),
                          .A(HOLDOFF_ADDR),
                          .CE(1'b1),
                          .CLK(aclk),
                          .Q(trig_holdoff_dly));

    // if trigger, set, else clear when aclk_phase_buf[1].
    reg trigger_stretch = 0;
    // recapture in ifclk to simplify
    reg trigger_ifclk = 0;
    
    // same behavior as the TURF and as run_dbg
    (* CUSTOM_MC_DST_TAG = "RUNRST RUNSTOP" *)
    reg trig_running = 0;
    // address to capture
    reg [11:0] current_address = {12{1'b0}};
    
    // captured address    
    reg [11:0] trig_address = {12{1'b0}};
    // write into the FIFO (just reregistered trigger_ifclk)
    reg trig_write = 0;
            
    // aclk_phase_i = cycle 0
    // aclk_phase_buf[0] = cycle 1
    // aclk_phase_buf[1] = cycle 2 (-> going into ifclk domain)        
    reg [1:0] aclk_phase_buf = {2{1'b0}};
    
    // HERE'S THE TRIGGER WOOOOO
    wire [47:0] dsp_C = dsp_trig_in;
    wire [47:0] dsp_AB = ~dsp_mask_in;
    // WOOT we're actually using the logic-y stuff
    //              opmode3:2       alumode3:0
    // x and z      00              1100
    // x and not z  00              1101
    // not x and z  10              1111
    // we want x and z, since A:B is X and C is Z
    // we could use the pattern detector only but we don't get double registers for free then.
    // no P reg because the pattern stuff is confusing.
    localparam [47:0] PATTERN = {48{1'b0}};
    localparam [47:0] MASK = {48{1'b0}};

    wire [8:0] dsp_OPMODE = { 2'b00, `Z_OPMODE_C, `Y_OPMODE_0, `X_OPMODE_AB };
    wire [3:0] dsp_ALUMODE = 4'b1100;                        
    wire [4:0] dsp_INMODE = {5{1'b0}};
    
    (* CUSTOM_CC_DST = ACLKTYPE *)
    DSP48E2 #(`CONSTANT_MODE_ATTRS,
              `NO_MULT_ATTRS,
              `DE2_UNUSED_ATTRS,
              .ACASCREG(2),
              .AREG(2),
              .BCASCREG(2),
              .BREG(2),
              .CREG(1),
              .PREG(0),
              .PATTERN(PATTERN),
              .MASK(MASK),
              .SEL_MASK("MASK"),
              .SEL_PATTERN("PATTERN"),
              .USE_PATTERN_DETECT("PATDET"))
        u_trig_dsp(.CLK(aclk),
                   .A( `DSP_AB_A(dsp_AB)),
                   .B( `DSP_AB_B(dsp_AB)),
                   .C( dsp_C ),
                   .CEA1( mask_wr_i[0] ),
                   .CEB1( mask_wr_i[1] ),
                   .CEA2( mask_update_i ),
                   .CEB2( mask_update_i ),
                   .CEC( 1'b1 ),
                   .RSTC(1'b0),
                   .RSTA(1'b0),
                   .RSTB(1'b0),
                   `D_UNUSED_PORTS,
                   .PATTERNDETECT(not_trigger));
                                                       
    always @(posedge aclk) begin
        trigin_rereg <= trig_i;
    
        if (trig_gen_rst[1]) trigger <= 1'b0;
        else trigger <= !not_trigger;
    
        aclk_phase_buf <= { aclk_phase_buf[0], aclk_phase_i };

        trigger_registered <= trigger && !trig_holdoff;

        if (trig_holdoff_complete) trig_holdoff <= 0;
        else if (trigger) trig_holdoff <= 1;        

        trig_holdoff_complete <= trig_holdoff_dly;
        
        if (trigger_registered) trigger_stretch <= 1;
        else if (aclk_phase_buf[1]) trigger_stretch <= 0;
    end
    
    always @(posedge ifclk) begin
        if (runrst_i) trig_running <= 1;
        else if (runstop_i) trig_running <= 0;
        
        if (!trig_running) current_address <= 12'd1;
        else current_address <= current_address + 1;

        trigger_ifclk <= trigger_stretch;
        if (trigger_ifclk) trig_address <= current_address;
        
        trig_write <= trigger_ifclk;
    end
    
    // now just buffer it and send it out
    // bottom 16 bits are zippo
    trig_gen_fifo u_fifo(.clk(ifclk),
                         .wr_en(trig_write),
                         .din( { 2'b10, trig_address, 2'b00,
                                 16'h0000 } ),
                         .rd_en(trig_tvalid && trig_tready),
                         .valid(trig_tvalid),
                         .dout(trig_tdata));        
endmodule
