`timescale 1ns / 1ps

`include "debug_enable.vh"

`include "interfaces.vh"
`include "pueo_beams_09_04_25.sv"
`include "pueo_dummy_beams.sv"

import pueo_beams::NUM_BEAM;
import pueo_dummy_beams::NUM_DUMMY;

`define NUM_V2_BEAMS 46

// There are very few RevA/RevB differences for the PL:
// SYSCLK moves from AG17/AH17 to AH15/AG15
// PLCLK_P/N at 122/124 becomes OE_AUXCLK/OE_AUXMGT:
// since the IOSTANDARDs/etc. stay the same.
// 
// But CLK8_P/N stays unused in revB (and L13_N/P were unused in revA)
// so we just manage it with a parameter.
// There *are* differences for the PS so that has to be handled separately.
// `define USE_INTERPHI
module pueo_surf6 #(parameter IDENT="SURF",
                    parameter REVISION="B",
                    parameter DEVICE="GEN3",
                    parameter USE_LF = "FALSE",
                    parameter [3:0] VER_MAJOR = 4'd0,
                    parameter [3:0] VER_MINOR = 4'd6,
                    parameter [7:0] VER_REV = 8'd42,
                    // this gets autofilled by pre_synthesis.tcl
                    parameter [15:0] FIRMWARE_DATE = {16{1'b0}},
                    // we have multiple GTPCLK options
                    // B128_CLK0 and B129_CLK0 both come from the Si5395
                    // B128_CLK1 comes from the LMK.
                    // B129_CLK1 comes from a standalone clock.
                    parameter GTPCLK = "B129_CLK1")
                    (
        // This clock is always running, no matter what.
        // The PS figures out what clocks are available at startup
        // and selects them.
        // This is 375 MHz, and is stepped down to 62.5 MHz internally
        // for registers, and used to run all the trigger logic.
        // It's 375 MHz because we can't afford the jitter from the MMCM.        
        input SYSREFCLK_P,  // revA AG17
        input SYSREFCLK_N,  // revA AH17
        // revB - NC in revA
        input SYSCLK_P,     // revB AH15 (inverted)
        input SYSCLK_N,     // revB AG15 (inverted)
        // revB - NC in revA
        input PL_SYSREF_P,  // revB AK18
        input PL_SYSREF_N,  // revB AL18
        // We name these by their TE0835 names
        inout B88_L5_P,     // PL_SYSREF_P in revA, OE_AUXCLK in revB - F14
        inout B88_L5_N,     // PL_SYSREF_N (unused) in revA, OE_AUXMGT in revB - F13
        // These are GPIOs (all nominal LEDs)
        output READY_B,         // B88_L8_N - D12
        output [1:0] FP_LED,    // B88_L8_P, B88_L10_P - E12, C14
        output [3:0] DBG_LED,   // AD18, AF18, AH18, AJ18
        // THESE HAVE THE DUMBEST NAMES
        // IT'S CALLED CAL_SEL because it's a CALIBRATION SELECTION
        // IT'S CALLED SEL_CAL because you're SELECTING CALIBRATION
        output CALEN,           // B88_L10_N - B13
        output CAL_SEL_B,       // CAL_SEL/CAL_SEL_B select between PULSE_P/N and CAL - A14
        output B88_L11_N,       // CAL_SEL or CLK_RST_B - A13
        output SEL_CAL_B,       // B88_L12_P - B12 - SEL_CAL/SEL_CAL_B - select cal or signal
        output SEL_CAL,         // B88_L12_N - A12
        // input refclk from TURFIO.
        input RXCLK_P,      // L12N AK16
        input RXCLK_N,      // L12P AJ17
        // THIS IS NOW RACKCTL_P/N
        inout TXCLK_P,     // L6P AN18
        inout TXCLK_N,     // L6N AP17
        // input commands from TURFIO
        input CIN_P,        // L4N AM16
        input CIN_N,        // L4P AL17
        // output responses/trigger data
        output COUT_P,      // L3P AP16
        output COUT_N,      // L3N AP15
        // data output
        output DOUT_P,      // L5N AN17
        output DOUT_N,      // L5P AM17
        // pulse output
        output PULSE_P,     // L2N AN15
        output PULSE_N,     // L2P AM15
        // Test points
        output TP2,
        output TP3,
        // UART commanding path input. These can be piped through EMIO too.
        // For some *totally* insane reason I flopped these between revisions
        // The pin pairs are
        // RevB - J3.53 to J2.140 = B88_L9_N = C13
        // RevA - J3.54 to J2.140
        // J2.138 = B88_L9_P = D13
        inout B88_L9_P,     // D13 revA RX, revB TX
        inout B88_L9_N,     // C13 revA TX, revB RX
        // Clock input. Right now I'm making this an input to us.
        input CLK_SDO_SYNC, // pin 15 B65_L11P AJ16
        // B128 GTP clocks
        input [1:0] B128_CLK_P, // 0: M28, 1: K28
        input [1:0] B128_CLK_N, // 0: M29, 1: K29        
        input [1:0] B129_CLK_P, // 0: H28, 1: F28
        input [1:0] B129_CLK_N, // 0: H29, 1: F29
        // RFSOC
        input DAC_CLK_P,
        input DAC_CLK_N,
        output DAC_OUT_P,
        output DAC_OUT_N,
        input SYSREF_P,
        input SYSREF_N,
        `ifdef USE_INTERPHI
        input [7:0] INTERPHI_RXP,
        input [7:0] INTERPHI_RXN,
        output [7:0] INTERPHI_TXP,
        output [7:0] INTERPHI_TXN,
        `endif
        input [3:0] ADC_CLK_P,
        input [3:0] ADC_CLK_N,
        input [7:0] ADC_IN_P,
        input [7:0] ADC_IN_N        
    );
    
    // Build triggers off of the versioning.
    localparam USE_V3 = (VER_MINOR == 4'd5) ? "FALSE" : "TRUE";
    localparam FULL_BEAMS = (USE_LF == "TRUE") ? 48 : ((USE_V3 == "TRUE") ? NUM_BEAM : `NUM_V2_BEAMS);
    
    localparam LF_TRIGGER_TYPE = "LFV";

    localparam TRIGGER_TYPE = (USE_LF == "TRUE") ? LF_TRIGGER_TYPE : ((USE_V3 == "TRUE") ? "V31500" : "V2");

//    localparam NBEAMS = VER_REV[0] ? NUM_DUMMY : FULL_BEAMS;
    // no more dummy builds
    localparam NBEAMS = FULL_BEAMS;
    localparam USE_BIQUADS = (USE_LF == "TRUE") ? "FALSE" : "FALSE";
    
    // ok, this is getting ridiculous, so just shift to another register.
    localparam [31:0] MIE_TRIGGER_VERSION = 3;
    // set bit 8 if biquads exist
    localparam [31:0] MIE_TRIGGER_CONFIG = MIE_TRIGGER_VERSION + ((USE_BIQUADS == "TRUE") ? 32'h100 : 32'h0);
    // set bit 24 if it's LF
    localparam [31:0] LF_TRIGGER_VERSION = 3 + 32'h1000000;
    // set bit 16 if it's LF vpol
    localparam [31:0] LF_TRIGGER_CONFIG = LF_TRIGGER_VERSION + ((LF_TRIGGER_TYPE == "LFV") ? 32'h10000 : 32'h0);
    
    localparam [31:0] TRIGGER_CONFIG = (USE_LF == "TRUE") ? LF_TRIGGER_CONFIG : MIE_TRIGGER_CONFIG;
        
    `ifdef USE_INTERPHI
    localparam IBERT = "TRUE";
    `else
    localparam IBERT = "FALSE";
    `endif
    
    localparam INV_COUT = 1'b0;
    localparam INV_CIN = 1'b1;
    localparam INV_DOUT = 1'b1;
    localparam INV_RXCLK = 1'b1;
    localparam INV_TXCLK = 1'b0;

    localparam [15:0] FIRMWARE_VERSION = { VER_MAJOR, VER_MINOR, VER_REV };
    localparam [31:0] DATEVERSION = { (USE_LF=="TRUE" ? 1'b0 : 1'b1),FIRMWARE_DATE[14:0], FIRMWARE_VERSION };

    localparam NUM_GPO = 8;
    
    // determined empirically
    localparam [4:0] SYNC_OFFSET_DEFAULT = 7;
    
    // This is the WISHBONE clock. Right now we're using the PS clock.
    wire wb_clk;
    localparam WB_CLK_TYPE = "PSCLK";        
    (* KEEP = "TRUE" *)
    wire ps_clk;
    assign wb_clk = ps_clk;

    // PIN REVISION HANDLING
    // 375 MHz system clock.
    wire aclk_in;
    wire aclk;
    // tclk is the trigger path clock, it is SHUT DOWN at start to conserve power
    // on hot days
    wire tclk;
    // PL sysref
    wire pl_sysref;
    // command tx input (from other SURF)/data/tristate, command rx, and the watchdog null wakeup
    wire cmd_tx_i;
    wire cmd_tx_d;
    wire cmd_tx_t;
    wire cmd_rx;
    wire watchdog_null;     // forces a NULL byte into the UART to affect a wakeup
    wire watchdog_trigger;  // indicates that we're gonna go boom
    // revB clk reset
    wire clk_rst_b;
    // The GPOs are
    // 0: nREADY
    // 1: FP_LEDA
    // 2: FP_LEDB
    // 3: CAL_SEL (inverted partners autogenerated as needed)
    // 4: SEL_CAL (inverted partners autogenerated as needed)
    // 5: disable AUXCLK (OE_AUXCLK inverted) - unused in revA
    // 6: disable MGTCLK (OE_MGTCLK inverted) - unused in revA
    // 7: firmware loading mode
    wire [NUM_GPO-1:0] idctrl_gpo;

    // this indicates that we've seen a MODE1_RST command
    // since rackclk became OK: because MODE1_RST is sent
    // after the TURFIO exits training, this is basically an
    // "exiting training" indicator.    
    wire mode1_ready;

    // this allows CLK_SDO_SYNC to be a sticky loss of lock detect
    // 0x99:
    //        SYNC_MUX_SEL[2:0] = 1xx
    //        SYNC_OUTPUT_INV = 1
    // = 128 | 8 = 0x88
    // SYNC_INT_MUX is 0x141:
    //      = 2 (PLL2 LOCK DETECT)
    // = 2
    // IOTEST_SYNC is 0x142
    //      SYNC_OUTPUT_HIZ = 0
    //      SYNC_ENB_INSTAGE = 1
    // = 0x30 is fine
    reg lol_sticky = 0;
    reg [1:0] sdo_sync_rereg = 2'b00;
    reg [4:0] sdo_counter = {5{1'b0}};
    always @(posedge wb_clk) begin
        sdo_sync_rereg <= { sdo_sync_rereg[0], CLK_SDO_SYNC };
        if (idctrl_gpo[0]) lol_sticky <= 0;
        else if (sdo_sync_rereg[1]) lol_sticky <= 1;        
        
        if (sdo_sync_rereg[0] ^ sdo_sync_rereg[1]) sdo_counter <= {5{1'b0}};
        else sdo_counter <= sdo_counter + 1;
    end

        
    // bit 7: firmware loading complete
    wire [NUM_GPO-1:0] idctrl_gpi;
    wire [1:0] firmware_pscomplete;
    assign idctrl_gpi[7:6] = firmware_pscomplete;  
    assign idctrl_gpi[5] = lol_sticky;
    assign idctrl_gpi[4] = mode1_ready;

    wire firmware_loading = idctrl_gpo[7];
    wire clocks_ready = idctrl_gpo[0];
    wire tclock_ready = idctrl_gpo[6];
    generate
        if (REVISION == "B") begin : REVB
            // ACLK comes from SYSCLK_P/N, and has names inverted (but is correct b/c of inversion at clock)
            IBUFDS_DIFF_OUT_IBUFDISABLE #(.SIM_DEVICE("ULTRASCALE"))
                                        u_aclk_ibuf(.I(SYSCLK_N),.IB(SYSCLK_P),
                                                    .IBUFDISABLE(1'b0),
                                                    .O(aclk_in));
            // PL_SYSREF comes from PL_SYSREF_P/N
            IBUFDS u_sysref_ibuf(.I(PL_SYSREF_P),.IB(PL_SYSREF_N),.O(pl_sysref));
            // cmd_tx goes to B88_L9_P
            IOBUF u_cmdtx_obuf(.I(cmd_tx_d),.O(cmd_tx_i),.T(cmd_tx_t),.IO(B88_L9_P));
            // cmd_rx comes from B88_L9_N
            IOBUF u_cmdrx_ibuf(.IO(B88_L9_N),.T(1'b1),.I(1'b0),.O(cmd_rx));
            // handle clk reset
            OBUFT u_clkrst_obuf(.I(1'b0),.T(clk_rst_b),.O(B88_L11_N));

            // OK, because the MGTs are now unused COMPLETELY we'll gang them
            // to the same GPO to free up one and default it to zero.
            wire en_mgt_clks = idctrl_gpo[5];
            IOBUF u_oe_auxclk_obuf(.I(1'b0),.T(en_mgt_clks),.IO(B88_L5_P));
            IOBUF u_oe_mgtclk_obuf(.I(1'b0),.T(en_mgt_clks),.IO(B88_L5_N));
        end else begin : REVA
            // ACLK comes from SYSREFCLK_P/N
            // We do NOT SUPPRESS ACLK at the input buffer! It's not glitch free
            // that way!!!
            // It is disabled at the BUFG and the PLLs are in reset until
            // it's ready.
            IBUFDS_DIFF_OUT_IBUFDISABLE #(.SIM_DEVICE("ULTRASCALE"))
                                        u_aclk_ibuf(.I(SYSREFCLK_P),.IB(SYSREFCLK_N),
                                                    .IBUFDISABLE(1'b0),
                                                    .O(aclk_in));
            // PL_SYSREF comes from B88_L5_P
            IOBUF u_sysref_ibuf(.IO(B88_L5_P),.T(1'b1),.I(1'b0),.O(pl_sysref));
            // B88_L5_N is unused
            IOBUF u_unused_ibuf(.IO(B88_L5_N),.T(1'b1),.I(1'b0));
            // cmd_tx goes to B88_L9_N
            IOBUF u_cmdtx_obuf(.I(cmd_tx_d),.O(cmd_tx_i),.T(cmd_tx_t),.IO(B88_L9_N));
            // cmd_rx comes from B88_L9_P
            IOBUF u_cmdrx_ibuf(.IO(B88_L9_P),.T(1'b1),.I(1'b0),.O(cmd_rx));
            // handle cal_sel
            OBUF u_calsel_obuf(.I(idctrl_gpo[3]),.O(B88_L11_N));
            // oe_auxclk/oe_mgtclk aren't in PL for revA
        end
    endgenerate

    // don't actually *use* this, but...
    OBUFT u_nready_obuf(.I(1'b0),.T(~clocks_ready),.O(READY_B));
    assign FP_LED = idctrl_gpo[2:1];
    assign CAL_SEL_B = ~idctrl_gpo[3];
    // OMFG YOU IDIOT:
    // U13 (and all the other SKY13323s have:
    // P2 = SIGNAL INPUT
    // P1 = CAL INPUT
    // SELCAL = VCTL2
    // SELCAL_B = VCTL1
    // But the truth table for SKY13323 is
    //                  VCTL1(SELCAL_B)       VCTL2(SELCAL)
    // P2 to COM        0                       1
    // P1 to COM        1                       0
    // 
    // meaning SEL_CAL needs to be idctrl_gpo[4] INVERTED, YOU IDIOT
    assign SEL_CAL = ~idctrl_gpo[4];
    assign SEL_CAL_B = idctrl_gpo[4];
    // NO dumbass if idctrl_gpo[4] is LOW we want SHDN = 1 so !SHDN = 0
    assign CALEN = idctrl_gpo[4];
    (* CUSTOM_CC_DST = "SYSREFCLK" *)
    BUFGCE #(.CE_TYPE("SYNC")) u_aclk_bufg(.I(aclk_in),.O(aclk),.CE(clocks_ready));
    (* CUSTOM_CC_DST = "SYSREFCLK" *)
    BUFGCE #(.CE_TYPE("SYNC")) u_tclk_bufg(.I(aclk_in),.O(tclk),.CE(tclock_ready));
            
    // let's just try "reset until the goddamn thing lines up"
    wire aclk_reset;
    // Interface clock. This is 125 MHz and 250 MHz. ifclk is also used to phase up aclk/memclk
    wire ifclk;
    wire ifclk_x2;
    // 500 MHz for URAM.
    wire memclk;
    wire memclk_phase;
    (* KEEP = "TRUE" *)
    wire aclk_phase;
    
    wire sync;
    wire ifclk_sync;
    (* KEEP = "TRUE" *)
    wire memclk_sync;
    // indicates in a register whether any sync has been seen. this should always be set if NOOP_LIVE is seen
    // but whatevers
    wire wbclk_do_sync;
    // indicates in a register whether a valid NOOP_LIVE has been seen.
    wire wbclk_noop_live;

    // Factor out the clocks into their own module
    // to allow us to test swapping them.
    wire aclk_locked;    
    clock_generator #(.MODE("PLL"))
        u_clkgen(.aclk_in_i(aclk_in),
                 .aclk_i(aclk),
                 .rst_i(aclk_reset),
                 .ifclk_o(ifclk),
                 .ifclk_x2_o(ifclk_x2),
                 .memclk_o(memclk),
                 .locked_o(aclk_locked));
                            
    // Note that we DO NOT use the PS's AXI4 interface!
    // Why? Because it both costs quite a bit of logic, and we would need
    // to mux in our own interface from the SFC to access the same space.
    //
    // Because *none* of this is speed critical, we instead implement
    // a simple WISHBONE-style register space using the serial port.
    // The PS can read/write our internal registers by setting an EMIO GPIO
    // and writing the same packets to the serial port that the SFC
    // can send.

    // GTP clocks
    wire gtp_clk;
    wire gtp_mgtclk;
    wire gtp_mgtaltclk;
    wire gtp_inclk;
    // sooo tedious
    generate
        if (GTPCLK == "B128_CLK1") begin : B128CLK1
            IBUFDS_GTE4 u_gtpclk(.I(B128_CLK_P[1]),.IB(B128_CLK_N[1]),.CEB(1'b0),.ODIV2(gtp_inclk),.O(gtp_mgtclk));            
            IBUFDS_GTE4 u_gtpaltclk(.I(B128_CLK_P[0]),.IB(B128_CLK_N[0]),.CEB(1'b0),.ODIV2(),
                                    .O(gtp_mgtaltclk));
        end else if (GTPCLK == "B129_CLK1") begin : B129CLK1
            IBUFDS_GTE4 u_gtpclk(.I(B129_CLK_P[1]),.IB(B129_CLK_N[1]),.CEB(1'b0),.ODIV2(gtp_inclk),.O(gtp_mgtclk));
            IBUFDS_GTE4 u_gtpaltclk(.I(B129_CLK_P[0]),.IB(B129_CLK_N[0]),.CEB(1'b0),.ODIV2(),
                                    .O(gtp_mgtaltclk));
        end else if (GTPCLK == "B128_CLK0") begin : B128CLK0
            IBUFDS_GTE4 u_gtpclk(.I(B128_CLK_P[0]),.IB(B128_CLK_N[0]),.CEB(1'b0),.ODIV2(gtp_inclk),.O(gtp_mgtclk));
            IBUFDS_GTE4 u_gtpaltclk(.I(B128_CLK_P[1]),.IB(B128_CLK_N[1]),.CEB(1'b0),.ODIV2(),
                                    .O(gtp_mgtaltclk));            
        end else if (GTPCLK == "B129_CLK0") begin : B129CLK0
            IBUFDS_GTE4 u_gtpclk(.I(B129_CLK_P[0]),.IB(B129_CLK_N[0]),.CEB(1'b0),.ODIV2(gtp_inclk),.O(gtp_mgtclk));
            IBUFDS_GTE4 u_gtpaltclk(.I(B129_CLK_P[1]),.IB(B129_CLK_N[1]),.CEB(1'b0),.ODIV2(),
                                    .O(gtp_mgtaltclk));
        end            
    endgenerate
    BUFG_GT u_gtpclk_bufg(.I(gtp_inclk),.O(gtp_clk));
    
    // RXCLK-based clocks.

    // This is the raw rxclk which doesn't go through an MMCM at all.
    wire rackclk;
    wire rxclk;
    wire clk300;
    
    // clock running indicators
    wire aclk_ok;       // aclk turns off if the clock synth isn't programmed
    wire rackclk_ok;    // rackclk turns off if the TURFIO isn't active
    wire rxclk_ok;      // rxclk can turn off if no rackclk or if the MMCM's off
    wire gtpclk_ok;     // gtpclk can be turned off by us or if the clock synth isn't prog'd
        
    // we have a 22-bit address space, so we can be generous

    // WISHBONE BUSSES
    // MASTERS
    `DEFINE_WB_IF( bm_ , 22, 32 );    // serial (temporary)
    `DEFINE_WB_IF( rack_ , 22, 32 );  // RACK control
    `DEFINE_WB_IF( spim_ , 22, 32 );
    // SLAVES
    // we have a 22-bit address space here, split up by 12 bits (1024 bytes, 256 32-bit regs)
    // we AUTOMATICALLY split it in 2 so that the UPPER address range directly goes to
    // the RF data converter since it wants an 18 bit address space
    // module 0: ID/ver/hsk                 0000 - 07FF
    // module 0b: TIO if                    0800 - 0FFF
    // (intermediate addresses are idctrl/TIO shadows)
    // module 1: levelone                   8000 - FFFF
    `DEFINE_WB_IF( surf_id_ctrl_ , 11, 32 );
    `DEFINE_WB_IF( tio_ , 11, 32);
    // Notch and AGC go to Lucas's trigger_chain_x8_wrapper.
    `DEFINE_WB_IF( levelone_ , 15, 32);
    `DEFINE_WB_IF( rfdc_ , 18, 32);
  
    // interconnect
    surf_intercon #(.DEBUG("FALSE"))
        u_intercon( .clk_i(wb_clk),
                    .rst_i(1'b0),
                    `CONNECT_WBS_IFM( bm_ , bm_ ),
                    `CONNECT_WBS_IFM( rack_ , rack_ ),
                    `CONNECT_WBS_IFM( spim_ , spim_ ),
                    
                    `CONNECT_WBM_IFM( surf_id_ctrl_ , surf_id_ctrl_ ),
                    `CONNECT_WBM_IFM( tio_ , tio_ ),
                    `CONNECT_WBM_IFM( levelone_ , levelone_ ),
                    `CONNECT_WBM_IFM( rfdc_ , rfdc_ ));

    // ok, here we go, folks
    wire rfdc_bridge_err;
    wire sysref_pl;
    wire [15:0] sysref_phase;
    wire rfdc_reset;
    rfdc_sync #(.DEBUG("TRUE"))
              u_sysref_sync(.sysclk_i(aclk),
                            .ifclk_i(ifclk),
                            .sysclk_sync_i(sync),
                            .sysref_i(pl_sysref),
                            .sysref_phase_o(sysref_phase),
                            .pl_sysref_o(sysref_pl));        
    localparam NCHAN = 8;
    localparam NSAMP = 8;
    localparam NBITS = 12;
    wire [NCHAN*NSAMP*NBITS-1:0] adc_dout;
    reg [NCHAN*NSAMP*NBITS-1:0] adc_dout_reg = {NCHAN*NSAMP*NBITS{1'b0}};
    reg [NCHAN*NSAMP*NBITS-1:0] pipe_reg = {NCHAN*NSAMP*NBITS{1'b0}};
    reg [NCHAN*NSAMP*NBITS-1:0] trig_dout_reg = {NCHAN*NSAMP*NBITS{1'b0}};
    always @(posedge aclk) adc_dout_reg <= adc_dout;
    always @(posedge tclk) begin
        trig_dout_reg <= adc_dout_reg;
//        pipe_reg <= adc_dout_reg;
//        trig_dout_reg <= pipe_reg;
    end        
    
    wire [7:0] adc_sig_detect;
    wire [7:0] adc_cal_frozen;
    wire [7:0] adc_cal_freeze;
    
    rfdc_wrapper #(.DEVICE(DEVICE),.NCLKS(4),.DEBUG("FALSE"))
        u_rfdc( .wb_clk_i(wb_clk),
                .wb_rst_i(1'b0),
                `CONNECT_WBS_IFM( wb_ , rfdc_ ),
                .bridge_err_o(rfdc_bridge_err),
                .aclk(aclk),
                .aresetn(!rfdc_reset),
                
                .adc_sig_detect(adc_sig_detect),
                .adc_cal_frozen(adc_cal_frozen),
                .adc_cal_freeze(adc_cal_freeze),                
                
                .sysref_p(SYSREF_P),
                .sysref_n(SYSREF_N),
                .sysref_pl_i(sysref_pl),
                .sysref_dac_i(sysref_pl),
                .dac_clk_p(DAC_CLK_P),
                .dac_clk_n(DAC_CLK_N),
                .adc_clk_p(ADC_CLK_P),
                .adc_clk_n(ADC_CLK_N),
                .adc_in_p(ADC_IN_P),
                .adc_in_n(ADC_IN_N),
                .dac_out_p(DAC_OUT_P),
                .dac_out_n(DAC_OUT_N),
                .adc_dout(adc_dout));

    // The V2 levelone has the generator embedded inside it.
    wire run_reset;
    wire run_stop;
    `DEFINE_AXI4S_MIN_IF( trigger_ , 32 );

    // TURF notch remote control
    wire notch_update;
    wire [5:0] notch0_byp;
    wire [5:0] notch1_byp;

    L1_trigger_wrapper_v2 #(.NBEAMS(NBEAMS),
                            .TRIGGER_TYPE(TRIGGER_TYPE),
                            .AGC_TIMESCALE_REDUCTION_BITS(1),
                            .USE_BIQUADS(USE_BIQUADS),
                            .WBCLKTYPE(WB_CLK_TYPE),
                            .CLKTYPE("SYSREFCLK"),
                            .IFCLKTYPE("IFCLK"))
        u_trigger(.wb_clk_i(wb_clk),
                  .wb_rst_i(!tclock_ready),
                  `CONNECT_WBS_IFM(wb_ , levelone_ ),
                  .aclk(aclk),
                  .aclk_phase_i(aclk_phase),
                  .tclk(tclk),
                  .dat_i(trig_dout_reg),
                  .ifclk(ifclk),
                  .ifclk_running_i(clocks_ready),
                  .runrst_i(run_reset),
                  .runstop_i(run_stop),
                  .notch_update_i(notch_update),
                  .notch0_byp_i(notch0_byp),
                  .notch1_byp_i(notch1_byp),
                  `CONNECT_AXI4S_MIN_IF(m_trig_ , trigger_ ));                  
                                              
//    wire [NBEAMS-1:0] levelone_trigger;
//    wire [47:0] levelone_mask;
//    wire [1:0]  levelone_mask_wr;
//    wire        levelone_mask_update;
//    wire        trig_gen_reset;
//    L1_trigger_wrapper #(.NBEAMS(NBEAMS),
//                         .AGC_TIMESCALE_REDUCTION_BITS(1),
//                         .USE_BIQUADS(USE_BIQUADS),
//                         .WBCLKTYPE(WB_CLK_TYPE),
//                         .CLKTYPE("SYSREFCLK"))
//        u_trigger(.wb_clk_i(wb_clk),
//                  .wb_rst_i(!tclock_ready),
//                  `CONNECT_WBS_IFM( wb_ , levelone_ ),
//                  .mask_o(levelone_mask),
//                  .mask_wr_o(levelone_mask_wr),
//                  .mask_update_o(levelone_mask_update),
//                  .gen_rst_o(trig_gen_reset),
//                  // i dunno what this does lol
//                  .reset_i(1'b0),
//                  .aclk(tclk),
//                  .dat_i(trig_dout_reg),
//                  .trigger_o(levelone_trigger));

//    `DEFINE_AXI4S_MIN_IF( trigger_ , 32 );
//    wire run_reset;
//    wire run_stop;
    
//    // these are all captured in ifclk now
//    wire [1:0] levelone_mask_wr_aclk;
//    wire levelone_mask_update_aclk;
//    flag_sync u_wr0_sync(.in_clkA(levelone_mask_wr[0]),
//                         .out_clkB(levelone_mask_wr_aclk[0]),
//                         .clkA(wb_clk),
//                         .clkB(ifclk));
//    flag_sync u_wr1_sync(.in_clkA(levelone_mask_wr[1]),
//                         .out_clkB(levelone_mask_wr_aclk[1]),
//                         .clkA(wb_clk),
//                         .clkB(ifclk));
//    flag_sync u_upd_sync(.in_clkA(levelone_mask_update),
//                         .out_clkB(levelone_mask_update_aclk),
//                         .clkA(wb_clk),
//                         .clkB(ifclk));                                                  
//    surf_trig_gen_v2 #(.ACLKTYPE("SYSREFCLK"),
//                       .IFCLKTYPE("IFCLK"),
//                       .DEBUG("TRUE"),
//                       .TRIG_CLOCKDOMAIN("ACLK"),
//                       .NBEAMS(NBEAMS))
//        u_triggen(.aclk(aclk),
//                  .aclk_phase_i(aclk_phase),
//                  .trig_i(levelone_trigger),
//                  .mask_i(levelone_mask),
//                  .mask_wr_i(levelone_mask_wr_aclk),
//                  .mask_update_i(levelone_mask_update_aclk),
//                  .gen_rst_i(trig_gen_reset),
//                  .ifclk(ifclk),
//                  .runrst_i(run_reset),
//                  .runstop_i(run_stop),
//                  `CONNECT_AXI4S_MIN_IF(trig_ , trigger_ ));
    
                
    // these are commands + trigger in
    wire [31:0] turf_command;
    wire        turf_command_valid;
    
    // command processor stream (in aclk domain)
    `DEFINE_AXI4S_MIN_IF( cmdproc_ , 8 );
    wire cmdproc_tlast;
    // reset command processor
    wire        cmdproc_reset;
    // firmware update stream (in aclk domain)
    `DEFINE_AXI4S_MIN_IF( fw_ , 8 );
    
    // uh to an LED or some'n
    wire        cmdproc_error;
    // these go to rackctl
    wire [23:0] cmd_addr_wbclk;
    wire [31:0] cmd_data_wbclk;
    wire        cmd_valid_wbclk;
    wire        cmd_ack_wbclk;
    
    cmdproc_buffer #(.WB_CLK_TYPE(WB_CLK_TYPE),.ACLK_TYPE("SYSREFCLK"))
                   u_buffer(.aclk(aclk),
                            .cmdproc_reset(cmdproc_reset),
                            `CONNECT_AXI4S_MIN_IF(cmdproc_ , cmdproc_ ),
                            .cmdproc_tlast(cmdproc_tlast),
                            .cmdproc_err_o(cmdproc_error),
                            .wb_clk_i(wb_clk),
                            .cmd_address_o(cmd_addr_wbclk),
                            .cmd_data_o(cmd_data_wbclk),
                            .cmd_valid_o(cmd_valid_wbclk),
                            .cmd_ack_i(cmd_ack_wbclk));


        
    // there IS NO RESPONSE STREAM ANYMORE
    // command response stream (in aclk domain)
    //    `DEFINE_AXI4S_MIN_IF( cmdresp_ , 8 );
    //    wire cmdresp_tlast;
    
    // trigger time
    wire [14:0] trigger_time;
    wire        trigger_time_valid;

    wire        run_dosync;
// defined above
//    wire        run_reset;
//    wire        run_stop;

    wire        pps;

    wire [1:0]  fw_mark;

    // this is the real real real command decoder now!
    pueo_command_decoder u_command_decoder(.sysclk_i(aclk),
                                           .command_i(turf_command),
                                           .command_valid_i(turf_command_valid),
                                           
                                           .wb_clk_i(wb_clk),
                                           .rundo_sync_wbclk_o(wbclk_do_sync),
                                           .runnoop_live_wbclk_o(wbclk_noop_live),
                                           
                                           .rundo_sync_o(run_dosync),
                                           .runrst_o(run_reset),
                                           .runstop_o(run_stop),

                                           .notch_update_o(notch_update),
                                           .notch0_byp_o(notch0_byp),
                                           .notch1_byp_o(notch1_byp),
                        
                                           
                                           .pps_o(pps),

                                           .cmdproc_rst_o(cmdproc_reset),
                                           `CONNECT_AXI4S_MIN_IF(cmdproc_ , cmdproc_ ),
                                           .cmdproc_tlast(cmdproc_tlast),

                                           `CONNECT_AXI4S_MIN_IF(fw_ , fw_ ),
                                           .fw_mark_o(fw_mark),
                                           
                                           .trig_time_o(trigger_time),
                                           .trig_valid_o(trigger_time_valid));
    (* IOB = "TRUE", CUSTOM_MC_DST_TAG = "RUNRST RUNSTOP" *)
    reg run_dbg = 0;  
    always @(posedge ifclk) begin
        if (run_reset) run_dbg <= 1;
        else if (run_stop) run_dbg <= 0;                                         
    end
    assign TP3 = run_dbg;
    
    // sync generation
    wire [4:0] sync_offset; // from idctrl
    
    // steal TP3
    wire dbg2_dummy;
    surf_sync_gen #(.SYNC_OFFSET_DEFAULT(SYNC_OFFSET_DEFAULT),
                    .USE_IOB2("FALSE"))
                  u_syncgen(.aclk_i(aclk),
                            .aclk_phase_i(aclk_phase),
                            .sync_req_i(run_dosync),
                            .sync_offset_i(sync_offset),
                            .memclk_i(memclk),
                            .memclk_phase_i(memclk_phase),
                            .ifclk_i(ifclk),
                            .dbg_sync_o( { dbg2_dummy, TP2 } ),
                            .sync_o(sync),
                            .sync_memclk_o(memclk_sync),
                            .sync_ifclk_o(ifclk_sync));

    // data output stream (in ifclk domain)
    wire [7:0] dout_data;
    wire       dout_data_valid;
    wire       dout_data_phase;

    localparam NUM_TURFIO_ERR = 1;
    wire [NUM_TURFIO_ERR-1:0] turfio_err;
    assign idctrl_gpi[0 +: NUM_TURFIO_ERR] = turfio_err;
    
    assign DBG_LED[0] = (|turfio_err) ? 1'b0 : 1'b1;
    assign DBG_LED[3:1] = 3'b111;    
    
    turfio_wrapper #(.INV_CIN(INV_CIN),
                     .INV_COUT(INV_COUT),
                     .INV_DOUT(INV_DOUT),
                     .INV_RXCLK(INV_RXCLK),
                     .INV_TXCLK(INV_TXCLK),
                     .WB_CLK_TYPE(WB_CLK_TYPE))
        u_turfio(.wb_clk_i(wb_clk),
                 .wb_rst_i(1'b0),
                 `CONNECT_WBS_IFM(wb_ , tio_ ),
                 
                 .aclk_i(aclk),
                 .aclk_ok_i(aclk_ok),
                 .aclk_locked_i(aclk_locked),
                 .aclk_reset_o(aclk_reset),
                 .aclk_phase_o(aclk_phase),
                 
                 .memclk_i(memclk),
                 .memclk_phase_o(memclk_phase),
                 
                 .ifclk_i(ifclk),
                 .ifclk_x2_i(ifclk_x2),
                 .ifclk_sync_i(ifclk_sync),
                 
                 .rackclk_o(rackclk),
                 
                 .rxclk_o(rxclk),
                 .clk300_o(clk300),
                 .rxclk_ok_i(rxclk_ok),
                 
                 .command_o(turf_command),
                 .command_valid_o(turf_command_valid),
                 `CONNECT_AXI4S_MIN_IF( s_trig_ , trigger_ ),
                 
                 .dout_data_i(dout_data),
                 .dout_data_valid_i(dout_data_valid),
                 .dout_data_phase_o(dout_data_phase),
                 
                 .turfio_err_o(turfio_err),
                 
                 .CIN_P(CIN_P),
                 .CIN_N(CIN_N),
                 .RXCLK_P(RXCLK_P),
                 .RXCLK_N(RXCLK_N),
                 .COUT_P(COUT_P),
                 .COUT_N(COUT_N),
                 //.TXCLK_P(TXCLK_P),
                 //.TXCLK_N(TXCLK_N),
                 .DOUT_P(DOUT_P),
                 .DOUT_N(DOUT_N));
        
    surf_id_ctrl #(.VERSION(DATEVERSION),
                   .TRIGGER_CONFIG(TRIGGER_CONFIG),
                   .WB_CLK_TYPE(WB_CLK_TYPE),
                   .NUM_GPO(NUM_GPO),
                   .SYNC_OFFSET_DEFAULT(SYNC_OFFSET_DEFAULT))
        u_id_ctrl(.wb_clk_i(wb_clk),
                  .wb_rst_i(1'b0),
                  `CONNECT_WBS_IFM(wb_ , surf_id_ctrl_ ),
                  .ifclk_i(ifclk),                  
                  .aclk_i(aclk),
                  .gtp_clk_i(gtp_clk),
                  .rxclk_i(rxclk),
                  .rackclk_i(rackclk),
                  
                  .adc_sigdet_i(adc_sig_detect),
                  .adc_cal_frozen_i(adc_cal_frozen),
                  .adc_cal_freeze_o(adc_cal_freeze),
                  
                  .rundo_sync_i(wbclk_do_sync),
                  .runnoop_live_i(wbclk_noop_live),
                  
                  .sysref_phase_i(sysref_phase),
                  .rfdc_rst_o(rfdc_reset),
                  
                  .gpi_i(idctrl_gpi),
                  .gpo_o(idctrl_gpo),
                  .sync_offset_o(sync_offset),
                  .hsk_rx_i(cmd_rx),
                  .hsk_tx_i(cmd_tx_i),
                  
                  .watchdog_null_o(watchdog_null),
                  .watchdog_trigger_o(watchdog_trigger),
                  
                  .rxclk_ok_o(rxclk_ok),
                  .aclk_ok_o(aclk_ok),
                  .gtpclk_ok_o(gtpclk_ok),
                  .rackclk_ok_o(rackclk_ok),
                  
                  .clk300_i(clk300));        
    //
    // Note that the UART path is a secondary commanding path, only for use
    // before the high-speed commanding path works. It is also an *addressed*
    // path because it is *common* between all the SURFs in a crate.

    // The SURFs get their address from USR_ACCESSE2 which is set in the firmware,
    // and nominally gets derived from the UUID in the PS. However in standalone
    // mode or early testing it'll just be whatever it's set to (typically zero).
    
    // only bottom 8 bits of address are used since we don't have >256 SURFs
    wire [31:0] my_full_address;
    wire [7:0] my_address = my_full_address[7:0];
    USR_ACCESSE2 u_addr_store(.DATA(my_full_address));
    
    // from the PS
    wire emio_rx;
    wire emio_tx;
    wire emio_sel;
    wire emio_wake;
    
    wire [1:0] emio_fwupdate;
    wire [1:0] emio_fwdone;
    
    wire bm_tx;
    wire bm_rx;
    
    // OK - we'll still allow emio_sel to have the serial
    // port become a WISHBONE bus, but now if it's *not*
    // set, we redirect the RACK serial port to it.
    // note: the RACK serial bus is inverted open drain
    // note note: we might actually retime the UART both
    // here and at the TURFIO to speed it up. Since it's
    // negative logic and we'll idle high, we can watch
    // for the first edge, and then stretch and delay
    // the output to deal with the open-drain asymmetry.
    // For this we just need to effectively measure the
    // risetime of the signal, and then we can do:
    // first edge -> wait risetime clocks before setting output low
    // sample again at bit time clock repeatedly
    // this should be pretty simple (just an accumulator really)
    // and deals with the fact that for an open drain signal
    // if we are trying to transmit 1010 and the bit period is 8
    // it ends up looking closer to
    //      /--- bit 0 here /--- bit 2 here
    // 1111_00000000000000110000000000000011_1111111
    //              \-- bit 1 here  \--- bit 3 here
    // Here the rise time would be 6 clocks, so if we retime it, we have
    // 1111111111_00000000111111110000000011111111_111111
    // obviously you need to fudge a little on the risetime/bit period
    wire cpu_rx = (watchdog_trigger) ? !watchdog_null : cmd_rx;
    assign emio_rx = (emio_sel) ? bm_tx : cmd_rx;

    assign cmd_tx_d = 1'b0;
    // emio_tx idles high, so we use it to drive cmd_tx_t automatically.
    // the way UARTs work, the start bit is always 0, and the stop bit is always 1.
    // the apparent risetime of the setup is around ~1 us, so if we retime
    // at the TURFIO we can probably get 460,800 baud, but we'll see.
    assign cmd_tx_t = (emio_sel) ? 1'b1 : emio_tx;
    assign bm_rx = (emio_sel) ? emio_tx : 1'b0;    

    // NOTE: FOR INITIAL TESTING ONLY -
    // NEED TO CREATE A SWITCHING BAUD RATE THINGY
    boardman_wrapper #(.USE_ADDRESS("TRUE"),
                       .CLOCK_RATE(100000000),
                       .BAUD_RATE(1000000))
            u_serial_if(.wb_clk_i(wb_clk),
                        .wb_rst_i(1'b0),
                        `CONNECT_WBM_IFM( wb_ , bm_ ),
                        .burst_size_i(2'b00),
                        .address_i(my_address),
                        .TX(bm_tx),
                        .RX(bm_rx));                      

    // HORSECRAP TO KEEP MEMCLK_SYNC
    reg [1:0] memclk_sync_rereg = {2{1'b0}};
    always @(posedge memclk) begin
        memclk_sync_rereg <= { memclk_sync_rereg[0], memclk_sync };
    end
    
    // EMIO GARBAGE
    // EMIO SPI DEFINES EVERY PIN AS TRISTATE BY DEFAULT (?!!)
    // SO WE HANDLE THAT CRAP IN THE WRAPPER
    wire spi_sclk;
    wire spi_mosi;
    wire spi_miso;
    wire spi_cs_b;

    // this will ultimately be our PL interface
    wb_spi_master #(.WB_CLK_TYPE(WB_CLK_TYPE))
        u_spim(.wb_clk_i(wb_clk),
               .wb_rst_i(1'b0),
               `CONNECT_WBM_IFM(wb_ , spim_),
               // one day I'll name this consistently
               .spi_cclk_i(spi_sclk),
               .spi_mosi_i(spi_mosi),
               .spi_miso_o(spi_miso),
               .spi_cs_i(spi_cs_b));
    
    
    
    wire [15:0] emio_gpio_i;
    wire [15:0] emio_gpio_o;
    wire [15:0] emio_gpio_t;

    // emio 0 is capture (legacy)
    // emio 1 is uart_sel (input)
    // emio 2 is wake (output)
    // emio 3 is clk_rst (input)
    assign emio_gpio_i[1:0] = 2'b00;
    assign emio_gpio_i[2] = emio_wake;
    assign emio_gpio_i[3] = 1'b0;
    assign emio_sel = emio_gpio_o[1] && !emio_gpio_t[1];    
    assign clk_rst_b = !emio_gpio_t[3] && emio_gpio_o[3] ? 0 : 1;

    // emio 4 is rackclk_ok, to detect TURFIO disappearing (note the state machine
    // checks via register path, but the main pysurfHskd checks via GPIOs)
    // The surf_id_ctrl register core also has a trigger for generating
    // a NULL byte on the UART when enabled - this will wake up the
    // processor if it's sleeping, at which point it'll run through
    // and check again. This is stupid but easier than setting up
    // an additional GPIO.
    // 500 kbaud = 2 us/bit = 20 us = 2000 100 MHz clocks.
    assign emio_gpio_i[4] = rackclk_ok;
    assign emio_gpio_i[7:5] = {3{1'b0}};
    
    // emio 9/8 is an interrupt (fwmarked[0]) (output)
    assign emio_gpio_i[8] = emio_fwupdate[0];
    assign emio_gpio_i[9] = emio_fwupdate[1];
    // emio 10-11 are isolated wake-uppable interrupts
    assign emio_gpio_i[11:10] = {2{1'b0}};
    
    // emio 15-12 are inputs: 12 is fwdone[0]
    assign emio_gpio_i[15:12] = {4{1'b0}};
    assign emio_fwdone[0] = emio_gpio_o[12] && !emio_gpio_t[12];
    assign emio_fwdone[1] = emio_gpio_o[13] && !emio_gpio_t[13];
     
    zynq_bd_wrapper #(.REVISION(REVISION)) u_pswrap( .UART_1_0_rxd( emio_rx ),
                              .UART_1_0_txd( emio_tx ),
                              .spi_mosi(spi_mosi),
                              .spi_miso(spi_miso),
                              .spi_sclk(spi_sclk),
                              .spi_cs_b(spi_cs_b),
                              .GPIO_0_0_tri_i( emio_gpio_i ),
                              .GPIO_0_0_tri_o( emio_gpio_o ),
                              .GPIO_0_0_tri_t( emio_gpio_t ),
                              .pl_clk0_0(ps_clk));

        
    // NOTE NOTE NOTE NOTE NOTE
    // THIS NEEDS TO BE CHANGED TO BE RUNNING OFF OF RACKCLK, NOT RXCLK
    // RXCLK DISAPPEARS WHEN THE MMCM RESETS, RACKCLK DOES NOT
    wb_rackctl_master #(.INV(INV_TXCLK),.DEBUG("TRUE"),
                        .WB_CLK_TYPE(WB_CLK_TYPE),
                        .RACKCLK_TYPE("RACKCLK"))
            u_wb_rackctl(.wb_clk_i(wb_clk),
                         .wb_rst_i(1'b0),
                         `CONNECT_WBM_IFM( wb_ , rack_ ),
                         .cmd_addr_i(cmd_addr_wbclk),
                         .cmd_data_i(cmd_data_wbclk),
                         .cmd_valid_i(cmd_valid_wbclk),
                         .cmd_ack_o(cmd_ack_wbclk),
                         .rackclk_i(rackclk),
                         .rackclk_ok_i(rackclk_ok),
                         .mode_i(1'b0),
                         .RACKCTL_P(TXCLK_P),
                         .RACKCTL_N(TXCLK_N));

    // ALL THE STUFF IN HERE
    wire [1:0] firmware_bank_writes;
    pueo_wrapper #(.MEMCLKTYPE("MEMCLK"),
                   .IFCLKTYPE("IFCLK"))
                 u_pueo(.aclk_i(aclk),
                        .aclk_sync_i(aclk_phase),
                        .memclk_i(memclk),
                        .memclk_sync_i(memclk_phase),
                        
                        .ifclk_i(ifclk),
                        
                        .ch_dat_i(adc_dout_reg),
                                                
                        .run_rst_i( run_reset ),
                        .run_stop_i( run_stop ),
                        
                        .trig_time_i( trigger_time ),
                        .trig_time_valid_i( trigger_time_valid ),
                        
                        .dout_data_o(dout_data),
                        .dout_data_valid_o(dout_data_valid),
                        .dout_data_phase_i(dout_data_phase),
                        
                        .fw_loading_i( firmware_loading ),
                        .fw_mark_i( fw_mark ),
                        .fwmon_wr_o( firmware_bank_writes ),
                        `CONNECT_AXI4S_MIN_IF( fw_ , fw_ ));

    surf6_fwu_marker u_fwu_marker(.sysclk_i(aclk),
                                  .ifclk_i( ifclk ),
                                  .fw_mark_i(fw_mark),
                                  .fw_wr_i( firmware_bank_writes ),
                                  .wb_clk_i(wb_clk),
                                  .fw_downloadmode_i(firmware_loading),
                                  .fw_pscomplete_o(firmware_pscomplete),
                                  .ps_fwupdate_gpo_o( emio_fwupdate ),
                                  .ps_fwdone_gpi_i( emio_fwdone ));

    surf6_mode1_monitor u_mode1_monitor(.wb_clk_i(wb_clk),
                                        .sysclk_i(aclk),
                                        .rackclk_ok_i( rackclk_ok ),
                                        .mode1rst_i( cmdproc_reset ),
                                        .mode1_ready_o( mode1_ready ));
            
//    // RACKCTL RESET
//    // The clock running monitors work like this:
//    // Every 64 clocks, ps_clock generates clk_running_will_reset, and 1 clock later we get clk_running_reset.
//    // Clock running reset clears a FF running in the destination domain, which is then set by the next edge.
//    // When the next clk_running_will_reset comes around, it captures that flop to see if a clock toggle
//    // has occurred.
//    // Therefore these resets turn on/off fairly fast, but they still can't happen within 64 clocks, so a 16-cycle
//    // reset window works fine.
//    wire rst_rackctl;
//    wire rst_rackctl_delay;
//    // Both this and the delay have to be cross-clock in order to make the recovery check happy.
//    (* CUSTOM_CC_SRC = "PSCLK" *)
//    reg rxclk_rst_psclk = 0;
//    always @(posedge ps_clk) rxclk_rst_psclk <= !rxclk_ok;
//    (* CUSTOM_CC_SRC = "PSCLK" *)
//    SRL16E u_rxclk_ok_delay(.CLK(ps_clk),.D(rxclk_rst_psclk),.CE(1'b1),.A0(1'b1),.A1(1'b1),.A2(1'b1),.A3(1'b1),.Q(rst_rackctl_delay));
//    (* CUSTOM_CC_DST = "RXCLK" *)
//    FDPE u_rackrst(.D(rst_rackctl_delay),.CE(1'b1),.C(rxclk),.PRE(rxclk_rst_psclk),.Q(rst_rackctl));
                                
//    // END RACKCTL RESET
//    wire [23:0] txn_addr;
//    wire [31:0] txn_data;
//    wire        txn_valid;
//    // TESTING
//    wire        txn_mode = txn_addr[23];
//    wire        txn_done = (txn_mode && txn_valid);    
//    wire [31:0] txn_resp = "SURF";   
//    rackctl_rxctl_sm_v1 #(.INV(INV_TXCLK),
//                          .DEBUG("TRUE"))
//        u_rackctl(.rxclk_i(rxclk),
//                  .rst_i(  rst_rackctl ),
//                  .mode_i( 1'b0 ),
//                  .txn_addr_o(txn_addr),
//                  .txn_data_o(txn_data),
//                  .txn_valid_flag_o(txn_valid),
//                  .txn_done_flag_i(txn_done),
//                  .txn_resp_i( txn_resp ),
//                  .mode1_txn_type_i(1'b0),
//                  .RACKCTL_P(TXCLK_P),
//                  .RACKCTL_N(TXCLK_N));         
    
//    turfio_bidir_test #(.INV(INV_TXCLK))
//        u_rackctl(.rxclk_i(rxclk),
//                  .RACKCTL_P(TXCLK_P),
//                  .RACKCTL_N(TXCLK_N));

    generate
        `ifdef USE_INTERPHI
        if (IBERT == "TRUE") begin : IB
            interphi_ibert_wrapper u_ibert(.INTERPHI_RXP(INTERPHI_RXP),
                                           .INTERPHI_RXN(INTERPHI_RXN),
                                           .INTERPHI_TXP(INTERPHI_TXP),
                                           .INTERPHI_TXN(INTERPHI_TXN),
                                           .gtp_clk_i(gtp_clk),
                                           .gtp_mgtclk_i(gtp_mgtclk),
                                           .gtp_mgtaltclk_i(gtp_mgtaltclk));
        end
        `endif
    endgenerate
    // savin' every bit of power we can folks
    // decouple sync
    reg sync_rereg = 1;
    always @(posedge aclk) sync_rereg <= !sync;
    wire no_pulse_needed = idctrl_gpo[3] || !idctrl_gpo[4];
    wire pulse;
    (* CUSTOM_IGN_DST = "SYSREFCLK" *)
    ODDRE1 #(.SRVAL(1'b1)) u_pulse(.C(aclk),.D1(sync_rereg),.D2(1'b1),.SR(no_pulse_needed),
                                   .Q(pulse));
    // purposefully inverted
    (* CUSTOM_IGN_DST = "SYSREFCLK" *)
    OBUFTDS u_pulse_obuf(.I(pulse),.T(no_pulse_needed),.O(PULSE_N),.OB(PULSE_P));


    `ifdef USING_DEBUG
    // just abuse this, whatever    
    lock_ila u_lock_ila(.clk(wb_clk),
                        .probe0(cmd_rx),
                        .probe1(cmd_tx_t),
                        .probe2(lol_sticky),
                        .probe3(sdo_counter));
    // still need these to monitor the UART path
    uart_vio u_vio(.clk(ps_clk),.probe_in0(emio_sel),.probe_out0(emio_wake));
    uart_ila u_ila(.clk(wb_clk),.probe0(bm_tx),.probe1(bm_rx));
    `endif

    
endmodule
