`timescale 1ns / 1ps
`include "interfaces.vh"
// 0x00 rst/EN_VTC/phase shift targets

// ACLK LAND
// 0x40 bit error count
// 0x44 cin capture
// 
// RXCLK LAND
// 0x80 primary idelay
// 0x84 primary odelay
// 0x88 monitor idelay
// 0x8C monitor odelay
//
// NOTE: COMPONENT MODE RESET SEQUENCE
// 1. EN_VTC IS HIGH (dis_vtc = 0)
// 2. RESET RXCLK MMCM
// 3. RESET IDELAYCTRL/ISERDES/IDELAY
// 4. RELEASE MMCM RESET
// 5. WAIT FOR LOCKED
// 6. RELEASE ISERDES/IDELAY RESET
// 7. RELEASE IDELAYCTRL RESET
// 8. WAIT FOR IDELAYCTRL RDY
//
// So we need to have a separate reset for ISERDES/IDELAY and IDELAYCTRL.
// REGISTER 0
// bit 0: CIN reset 
// bit 1: disable VTC
// bit 2: IDELAYCTRL reset
// bit 3: IDELAYCTRL ready
// bit 4: MMCM reset
// bit 5: MMCM ready
// bit 6: train enable COUT
// bit 7: train enable DOUT
// bit 8: bitslip reset
// bit 9: bitslip
// bit 10: lock reset
// bit 11: lock req
// bit 12: lock status
// bit 13: reset aclk plls
// bit 14: aclk plls are locked
// bit 15: ifclk alignment error
// bit 24-16: target PS value
// bit 30-25 - unused
// bit 31: PS is incomplete

// mmcm_rst, mmcm_rdy, train_enable, lock_req, lock_rst, bitslip_rst, dis_vtc, cin_rst
// {7{1'b0}}, lock_ok
// target_ps_value, ps_incomplete

// god this is such a giant mess
module turfio_register_core #(parameter WBCLKTYPE="PSCLK",
                              parameter ACLKTYPE="SYSREFCLK",
                              parameter RXCLKTYPE="RXCLK",
                              parameter CAPTURE_DATA_WIDTH = 4
)(
        input wb_clk_i,
        input wb_rst_i,
        `TARGET_NAMED_PORTS_WB_IF(wb_ , 11, 32),        

        input rxclk_i,
        input rxclk_ok_i,
        input aclk_i,
        input aclk_ok_i,
        
        input aclk_locked_i,
        output aclk_reset_o,
        input ifclk_alignerr_i,
        
        // cin active indicator. indicates a response to a train request at boot
        // (i.e. we can train now)
        input cin_active_i,
        output cin_active_rst_o,
                
        // mmcm & phase shift interface
        output ps_en_o,
        input ps_done_i,
        input mmcm_locked_i,
        output mmcm_rst_o,
        input capture_err_i,
                
        // idelay interface
        output cin_rst_o,
        output en_vtc_o,
        output delay_load_o,
        output delay_rd_o,
        output [1:0] delay_sel_o,
        output [8:0] delay_cntvaluein_o,
        input [8:0]  delay_cntvalueout_i,

        // idelayctrl
        input idelayctrl_rdy_i,
        output idelayctrl_rst_o,
                
        // capture and transfer interface  
        input cin_err_i,              
        output capture_req_o,
        output bitslip_rst_o,
        output bitslip_o,
        
        // lock interface
        output lock_rst_o,
        output lock_req_o,
        input lock_status_i,
        input cin_running_i,
        
        // training output
        output [1:0] train_en_o,
        
        input [CAPTURE_DATA_WIDTH-1:0] capture_data_i
    );

    localparam NUM_ADR_BITS = 11;

    // our phase shift needs to be enough to track the 125 MHz
    // delays: we need to make sure that the delays we use on all
    // SURFs is the same.
    // RXCLK has a multipler of 12, and phase shifts are 56x,
    // so 56*12 = 672 - needs 10 bits.
    // Note this is DIFFERENT than the TURFIO since our MMCM
    // runs at 1.5 GHz, not 1 GHz.
    localparam RXCLK_FINE_PS_MAX  = 672 - 1;    
    localparam RXCLK_FINE_PS_BITS = $clog2(RXCLK_FINE_PS_MAX);
    
    // spaces are split up
    localparam [NUM_ADR_BITS-1:0] CLOCK_DOMAIN_MASK     = 11'h0C0;
    localparam [NUM_ADR_BITS-1:0] WB_CLK_DOMAIN         = 11'h000;
    localparam [NUM_ADR_BITS-1:0] ACLK_DOMAIN           = 11'h040;
    localparam [NUM_ADR_BITS-1:0] RXCLK_DOMAIN          = 11'h080;
    
    localparam [NUM_ADR_BITS-1:0] REGISTER_MASK         = 11'h03F;
    
    localparam [NUM_ADR_BITS-1:0] CONTROL_REG           = 11'h000;
    localparam [NUM_ADR_BITS-1:0] ACLK_BIT_ERR_REG      = 11'h040;
    localparam [NUM_ADR_BITS-1:0] ACLK_CAPTURE_REG      = 11'h044;
    localparam [NUM_ADR_BITS-1:0] ACLK_CIN_ERR_REG      = 11'h048;
    
    localparam [NUM_ADR_BITS-1:0] PRIMARY_IDELAY_REG    = 11'h080;
    localparam [NUM_ADR_BITS-1:0] PRIMARY_ODELAY_REG    = 11'h084;
    localparam [NUM_ADR_BITS-1:0] MONITOR_IDELAY_REG    = 11'h088;
    localparam [NUM_ADR_BITS-1:0] MONITOR_ODELAY_REG    = 11'h08C;

    `define DOMAIN_MATCH( domain , adrval )  \
        ( (adrval & CLOCK_DOMAIN_MASK ) == (domain & CLOCK_DOMAIN_MASK))

    `define REGVAL_MATCH( regval , adrval)  \
        ( (adrval & REGISTER_MASK ) == (regval & REGISTER_MASK))        

    `define FULL_MATCH( domain, regval, adrval ) \
        ( `DOMAIN_MATCH( domain , adrval ) && `REGVAL_MATCH( regval , adrval ) )

    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg [31:0] dat_in_static = {32{1'b0}};
    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [31:0] dat_reg = {32{1'b0}};
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg [NUM_ADR_BITS-1:0] adr_in_static = {NUM_ADR_BITS{1'b0}};
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg [3:0] sel_in_static = {4{1'b0}};
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg we_in_static = 0;
    
    // these are checked in idle
    wire rxclk_access = `DOMAIN_MATCH( RXCLK_DOMAIN , wb_adr_i);
    wire aclk_access = `DOMAIN_MATCH( ACLK_DOMAIN , wb_adr_i);
    
    ///////// STATIC CLOCK CROSS
    (* CUSTOM_CC_DST = WBCLKTYPE, ASYNC_REG = "TRUE" *)
    reg [1:0] cin_active_wbclk = 2'b00;
    reg       cin_active_rst_wbclk = 0;
    flag_sync u_cin_active_rst_sync(.in_clkA(cin_active_rst_wbclk),.out_clkB(cin_active_rst_o),
                                    .clkA(wb_clk_i),.clkB(rxclk_i));
    
    ///////// RXCLK CLOCK CROSS HANDLING
    wire rxclk_waiting;
    reg rxclk_waiting_reg = 0;
    always @(posedge wb_clk_i) rxclk_waiting_reg <= rxclk_waiting;
    wire rxclk_waiting_flag_wbclk = (rxclk_waiting && !rxclk_waiting_reg);
    wire rxclk_waiting_flag_rxclk;
    flag_sync u_rxclk_waiting_sync(.clkA(wb_clk_i),.clkB(rxclk_i),
                                   .in_clkA(rxclk_waiting_flag_wbclk),
                                   .out_clkB(rxclk_waiting_flag_rxclk));
    reg rxclk_ack_flag_rxclk = 0;
    always @(posedge rxclk_i) rxclk_ack_flag_rxclk <= rxclk_waiting_flag_rxclk;
    wire rxclk_ack_flag_wbclk;
    flag_sync u_rxclk_ack_sync(.clkA(rxclk_i),.clkB(wb_clk_i),
                               .in_clkA(rxclk_ack_flag_rxclk),
                               .out_clkB(rxclk_ack_flag_wbclk));                                       
    
    ///////// ACLK CLOCK CROSS HANDLING
    wire aclk_waiting;
    reg aclk_waiting_reg = 0;
    always @(posedge wb_clk_i) aclk_waiting_reg <= aclk_waiting;
    wire aclk_waiting_flag_wbclk = (aclk_waiting && !aclk_waiting_reg);
    wire aclk_waiting_flag_aclk;
    flag_sync u_aclk_waiting_sync(.clkA(wb_clk_i),.clkB(aclk_i),
                                  .in_clkA(aclk_waiting_flag_wbclk),
                                  .out_clkB(aclk_waiting_flag_aclk));
    reg aclk_ack_flag_aclk = 0;
    always @(posedge aclk_i) aclk_ack_flag_aclk <= aclk_waiting_flag_aclk;
    wire aclk_ack_flag_wbclk;
    flag_sync u_aclk_ack_sync(.clkA(aclk_i),.clkB(wb_clk_i),
                              .in_clkA(aclk_ack_flag_aclk),
                              .out_clkB(aclk_ack_flag_wbclk));
    
    /////////////////////
    // BIT ERROR COUNTING
    /////////////////////
    // NOTE NOTE NOTE
    // I MIGHT JUST REPLACE THIS AND MUX THE ERROR INPUTS
    // IT'S KINDA STUPID TO DUPLICATE IT
    wire [24:0] aclk_bit_error_count;
    wire        aclk_bit_error_count_valid;
    reg         aclk_bit_error_count_valid_rereg = 0;
    always @(posedge aclk_i) aclk_bit_error_count_valid_rereg <= aclk_bit_error_count_valid;
    wire        aclk_bit_error_count_flag = aclk_bit_error_count_valid && !aclk_bit_error_count_valid_rereg;
    wire        aclk_bit_error_count_valid_wbclk;
    flag_sync   u_aclk_biterr_valid_sync(.in_clkA(aclk_bit_error_count_flag),
                                          .out_clkB(aclk_bit_error_count_valid_wbclk),
                                          .clkA(aclk_i),
                                          .clkB(wb_clk_i));
    wire        aclk_bit_error_count_ack;
    flag_sync   u_aclk_biterr_ack(.in_clkA(aclk_bit_error_count_valid_wbclk),
                                   .out_clkB(aclk_bit_error_count_ack),
                                   .clkA(wb_clk_i),
                                   .clkB(aclk_i));
    // this is a cross-clock target
    (* CUSTOM_CC_DST = WBCLKTYPE *)                                   
    reg [24:0]  aclk_bit_error_count_wbclk = {25{1'b0}};
    always @(posedge wb_clk_i)
        if (aclk_bit_error_count_valid_wbclk)
            aclk_bit_error_count_wbclk <= aclk_bit_error_count;                                       
    dsp_timed_counter #(.MODE("ACKNOWLEDGE"),.CLKTYPE_SRC(ACLKTYPE),.CLKTYPE_DST(ACLKTYPE))
        u_aclk_biterr(.clk(aclk_i),
                       .rst(aclk_bit_error_count_ack),
                       .count_in(capture_err_i),
                       .interval_in(dat_in_static[23:0]),
                       .interval_load( aclk_waiting_flag_aclk &&
                                       `REGVAL_MATCH( ACLK_BIT_ERR_REG , adr_in_static ) &&
                                       we_in_static ),
                       .count_out(aclk_bit_error_count),
                       .count_out_valid(aclk_bit_error_count_valid));
    /////////////////////
    // CIN ERROR COUNTING
    /////////////////////
    wire [24:0] aclk_cin_error_count;
    wire        aclk_cin_error_count_valid;
    reg         aclk_cin_error_count_valid_rereg = 0;
    always @(posedge aclk_i) aclk_cin_error_count_valid_rereg <= aclk_cin_error_count_valid;
    wire        aclk_cin_error_count_flag = aclk_cin_error_count_valid && !aclk_cin_error_count_valid_rereg;
    wire        aclk_cin_error_count_valid_wbclk;
    flag_sync   u_aclk_cinerr_valid_sync(.in_clkA(aclk_cin_error_count_flag),
                                          .out_clkB(aclk_cin_error_count_valid_wbclk),
                                          .clkA(aclk_i),
                                          .clkB(wb_clk_i));
    wire        aclk_cin_error_count_ack;
    flag_sync   u_aclk_cinerr_ack(.in_clkA(aclk_cin_error_count_valid_wbclk),
                                   .out_clkB(aclk_cin_error_count_ack),
                                   .clkA(wb_clk_i),
                                   .clkB(aclk_i));
    // this is a cross-clock target
    (* CUSTOM_CC_DST = WBCLKTYPE *)                                   
    reg [24:0]  aclk_cin_error_count_wbclk = {25{1'b0}};
    always @(posedge wb_clk_i)
        if (aclk_cin_error_count_valid_wbclk)
            aclk_cin_error_count_wbclk <= aclk_cin_error_count;                                       
    dsp_timed_counter #(.MODE("ACKNOWLEDGE"),.CLKTYPE_SRC(ACLKTYPE),.CLKTYPE_DST(ACLKTYPE))
        u_aclk_cinerr(.clk(aclk_i),
                       .rst(aclk_cin_error_count_ack),
                       .count_in(cin_err_i),
                       .interval_in(dat_in_static[23:0]),
                       .interval_load( aclk_waiting_flag_aclk &&
                                       `REGVAL_MATCH( ACLK_CIN_ERR_REG , adr_in_static ) &&
                                       we_in_static ),
                       .count_out(aclk_cin_error_count),
                       .count_out_valid(aclk_cin_error_count_valid));

    /////////////////////
    // CONTROLS
    /////////////////////

    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg cin_rst = 0;
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg dis_vtc = 0;
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg mmcm_rst = 0;
    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [1:0] mmcm_locked = {2{1'b0}};

    // these both START OUT in reset
    // because they're pulled OUT of reset
    // by the state machine once the incoming
    // clock is active. This ensures that
    // ACLK literally starts up 100% clean
    // with absolutely zero glitches
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg pll_reset = 1;
    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [1:0] pll_locked = {2{1'b0}};
    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [1:0] pll_align_err = {2{1'b0}};    
    
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg idelayctrl_rst = 0;
    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [1:0] idelayctrl_rdy = {2{1'b0}};
    
    // drop this back to a single bit to free up a bit for data active
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg train_enable = 0;

    reg bitslip_rst = 0;
    reg bitslip = 0;
    
    reg lock_rst = 0;
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg lock_req = 0;
    (* CUSTOM_CC_DST = ACLKTYPE *)
    reg [1:0] lock_req_aclk = {2{1'b0}};
    (* ASYNC_REG = "TRUE", CUSTOM_CC_DST = WBCLKTYPE *)
    reg [1:0] lock_status = 0;
    (* ASYNC_REG = "TRUE", CUSTOM_CC_DST = WBCLKTYPE *)
    reg [1:0] cin_running = 0;        
    
    reg [RXCLK_FINE_PS_BITS-1:0] current_ps_value = {RXCLK_FINE_PS_BITS{1'b0}};
    reg [RXCLK_FINE_PS_BITS-1:0] target_ps_value = {RXCLK_FINE_PS_BITS{1'b0}};
    reg ps_enable = 0;
    reg ps_waiting = 0;
    // I don't actually think this is necessary but whatever
    wire fine_ps_enable = ps_enable && !ps_waiting;
    reg ps_incomplete = 0;
    
    
    // okay, because we ran out of bits, we multiplex the
    // lock status bit. if lock_req = 1, then the bit is
    // locked. if lock_req = 0, then the bit is running.
    // We also change lock_req from a flag to a static value:
    // it doesn't matter because the parallelizer doesn't
    // care if it stays static.
    wire [31:0] control_register = 
        { ps_incomplete,
          {(15-RXCLK_FINE_PS_BITS){1'b0}},
          target_ps_value,

          pll_align_err[1],     // 15
          pll_locked[1],        // 14
          pll_reset,            // 13
          lock_req ? lock_status[1] : cin_running[1],       // 12
          lock_req,             // 11
          lock_rst,             // 10
          bitslip,              // 9
          bitslip_rst,          // 8
          cin_active_wbclk[1],  // 7 - on a write of 0 when 1 this is reset.
                                //     the logic is reversed to deal with read-modify-writes.
                                //     obviously no need to reset when it's zero already.
          train_enable,         // 6
          mmcm_locked[1],       // 5
          mmcm_rst,             // 4
          idelayctrl_rdy[1],    // 3
          idelayctrl_rst,       // 2
          dis_vtc,              // 1
          cin_rst };            // 0
    
    localparam FSM_BITS=2;
    localparam [FSM_BITS-1:0] IDLE = 0;
    localparam [FSM_BITS-1:0] ACK = 1;
    localparam [FSM_BITS-1:0] WAIT_ACK_RXCLK = 2;
    localparam [FSM_BITS-1:0] WAIT_ACK_ACLK = 3;
    reg [FSM_BITS-1:0] state = IDLE;
    
    assign rxclk_waiting = (state == WAIT_ACK_RXCLK);
    assign aclk_waiting = (state == WAIT_ACK_ACLK);
    
    always @(posedge wb_clk_i) begin
        // cin active clock cross
        cin_active_wbclk <= { cin_active_wbclk[0], cin_active_i };
        
        // PHASE SHIFT LOGIC
        if (target_ps_value != current_ps_value) begin
            if (ps_waiting) ps_enable <= 0;
            else ps_enable <= 1;
        end else ps_enable <= 0;
        
        if (ps_enable) ps_waiting <= 1;
        else if (ps_done_i) ps_waiting <= 0;
        
        if (fine_ps_enable) begin
            if (current_ps_value == RXCLK_FINE_PS_MAX) current_ps_value <= {RXCLK_FINE_PS_BITS{1'b0}};
            else current_ps_value <= current_ps_value + 1;
        end
        ps_incomplete <= !((target_ps_value == current_ps_value) && !ps_waiting);
        
        // REGISTER LOGIC
        if (state == ACK && we_in_static && `FULL_MATCH(WB_CLK_DOMAIN, CONTROL_REG, adr_in_static)) begin
            if (sel_in_static[0]) begin
                cin_rst <= dat_in_static[0];
                dis_vtc <= dat_in_static[1];
                idelayctrl_rst <= dat_in_static[2];
                mmcm_rst <= dat_in_static[4];
                train_enable <= dat_in_static[6];
                // this COULD still trip on a RMW if it becomes active
                // in the middle of the operation, but who cares, it'll just set
                // again immediately.
                cin_active_rst_wbclk <= !dat_in_static[7] && cin_active_wbclk[1];
            end
            if (sel_in_static[1]) begin
                bitslip_rst <= dat_in_static[8];
                bitslip <= dat_in_static[9];
                lock_rst <= dat_in_static[10];
                lock_req <= dat_in_static[11];
                pll_reset <= dat_in_static[13];
            end
            if (sel_in_static[3] && sel_in_static[2]) begin
                target_ps_value <= dat_in_static[16 +: RXCLK_FINE_PS_BITS];
            end
        end else begin
            // make these guys flags
            bitslip_rst <= 1'b0;
            bitslip <= 1'b0;
            // not a flag anymore
            //lock_req <= 1'b0;
            lock_rst <= 1'b0;
            cin_active_rst_wbclk <= 1'b0;
        end        
        
        lock_status <= { lock_status[0], lock_status_i };
        cin_running <= { cin_running[0], cin_running_i };
        idelayctrl_rdy <= { idelayctrl_rdy[0], idelayctrl_rdy_i };
        mmcm_locked <= { mmcm_locked[0], mmcm_locked_i };
        pll_locked <= { pll_locked[0], aclk_locked_i };
        pll_align_err <= { pll_align_err[0], ifclk_alignerr_i };
        
        // static capture
        if (wb_cyc_i && wb_stb_i) begin
            if (wb_sel_i[0]) dat_in_static[7:0] <= wb_dat_i[7:0];
            if (wb_sel_i[1]) dat_in_static[15:8] <= wb_dat_i[15:8];
            if (wb_sel_i[2]) dat_in_static[23:16] <= wb_dat_i[23:16];
            if (wb_sel_i[3]) dat_in_static[31:24] <= wb_dat_i[31:24];
            adr_in_static <= wb_adr_i;
            we_in_static <= wb_we_i;
            sel_in_static <= wb_sel_i;
        end
        
        if (wb_rst_i) state <= IDLE;
        else begin
            case (state)
                IDLE: if (wb_cyc_i  && wb_stb_i) begin
                    if (rxclk_access) state <= WAIT_ACK_RXCLK;
                    else if (aclk_access) state <= WAIT_ACK_ACLK;
                    else state <= ACK;
                end
                ACK: state <= IDLE;
                WAIT_ACK_RXCLK: if (rxclk_ack_flag_wbclk || !rxclk_ok_i) state <= ACK;
                WAIT_ACK_ACLK: if (aclk_ack_flag_wbclk || !aclk_ok_i) state <= ACK;
             endcase
         end
         
         if (state == WAIT_ACK_RXCLK) begin
            if (rxclk_ack_flag_wbclk) begin
                // this will get reduced
                if (`REGVAL_MATCH( PRIMARY_IDELAY_REG , adr_in_static ) ||
                    `REGVAL_MATCH( PRIMARY_ODELAY_REG , adr_in_static ) ||
                    `REGVAL_MATCH( MONITOR_IDELAY_REG , adr_in_static ) ||
                    `REGVAL_MATCH( MONITOR_ODELAY_REG , adr_in_static ) )
                    dat_reg <= { {23{1'b0}}, delay_cntvalueout_i };
                // rxclk side capture here
            end else if (!rxclk_ok_i) begin
                dat_reg <= {32{1'b1}};
            end
         end else if (state == WAIT_ACK_ACLK) begin
            if (aclk_ack_flag_wbclk) begin
                if (`REGVAL_MATCH( ACLK_BIT_ERR_REG , adr_in_static )) dat_reg <= aclk_bit_error_count_wbclk;
                // aclk side capture here
                else if (`REGVAL_MATCH( ACLK_CAPTURE_REG, adr_in_static)) dat_reg <= capture_data_i;
                else if (`REGVAL_MATCH( ACLK_CIN_ERR_REG, adr_in_static)) dat_reg <= aclk_cin_error_count_wbclk;
            end else if (!aclk_ok_i) begin
                dat_reg <= {32{1'b1}};
            end            
         end else begin
            // this SHOULDN'T MATTER but WHATEVER
            if (state == IDLE) begin
                // can qualify more but who cares
                if (wb_cyc_i && wb_stb_i)
                    dat_reg <= control_register;
            end                    
         end         
    end

    // pass out the flags
    flag_sync u_bitslip_rst_sync(.clkA(wb_clk_i),.clkB(aclk_i),
                                 .in_clkA(bitslip_rst),.out_clkB(bitslip_rst_o));
    flag_sync u_bitslip_sync(.clkA(wb_clk_i),.clkB(aclk_i),
                             .in_clkA(bitslip),.out_clkB(bitslip_o));
// not a flag anymore
//    flag_sync u_lockreq_sync(.clkA(wb_clk_i),.clkB(aclk_i),
//                             .in_clkA(lock_req),.out_clkB(lock_req_o));                                                             
    always @(posedge aclk_i) begin
        lock_req_aclk <= {lock_req_aclk[0], lock_req};
    end
    assign lock_req_o = lock_req_aclk[1];        
    flag_sync u_lockrst_sync(.clkA(wb_clk_i),.clkB(aclk_i),
                             .in_clkA(lock_rst),.out_clkB(lock_rst_o));
                                                          
    // assign out the constants
    assign cin_rst_o = cin_rst;
    assign en_vtc_o = !dis_vtc;                             
    assign train_en_o = {2{train_enable}};
    assign mmcm_rst_o = mmcm_rst;
    assign idelayctrl_rst_o = idelayctrl_rst;

    assign aclk_reset_o = pll_reset;

    assign capture_req_o = aclk_waiting_flag_aclk && `REGVAL_MATCH( ACLK_CAPTURE_REG , adr_in_static );

    // delays are spaced apart and apply when adr_static[7] is set
    assign delay_sel_o = adr_in_static[3:2];
    assign delay_load_o = (adr_in_static[7] && !adr_in_static[6] && we_in_static && sel_in_static[0] && sel_in_static[1])
                            && rxclk_waiting_flag_rxclk;
    assign delay_rd_o = (adr_in_static[7] && !adr_in_static[6] && !we_in_static)
                            && rxclk_waiting_flag_rxclk;
    assign delay_cntvaluein_o = dat_in_static[8:0];
    
    // wb outputs       
    assign wb_dat_o = dat_reg;
    assign wb_ack_o = (state == ACK);
    assign wb_err_o = 1'b0;
    assign wb_rty_o = 1'b0;
                                
    assign ps_en_o = fine_ps_enable;
                                
endmodule
