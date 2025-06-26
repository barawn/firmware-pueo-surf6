`timescale 1ns / 1ps
`include "interfaces.vh"
// Generates WISHBONE cycles from RACKctl transactions.
module wb_rackctl_master #(parameter INV = 1'b0,
                           parameter DEBUG = "FALSE",
                           parameter WB_CLK_TYPE = "NONE",
                           parameter RACKCLK_TYPE = "NONE")(
        input wb_clk_i,
        input wb_rst_i,
        `HOST_NAMED_PORTS_WB_IF( wb_ , 22, 32 ),
        // these come from the cmdproc_buffer
        // they're in wb clk domain
        input [23:0] cmd_addr_i,
        input [31:0] cmd_data_i,
        input cmd_valid_i,
        output cmd_ack_o,

        input rackclk_i,
        input rackclk_ok_i,
        // mode switch
        input mode_i,
        inout RACKCTL_P,
        inout RACKCTL_N
    );
    
    localparam MODE0 = 0;
    localparam MODE1 = 1;
    
    // capture mode in wbclk
    (* CUSTOM_CC_SRC = WB_CLK_TYPE *)
    reg mode = MODE0;
    
    // and pass to sysclk
    (* CUSTOM_CC_DST = RACKCLK_TYPE *)
    reg [1:0] mode_rackclk = {2{1'b0}};
    
    // address captured in mode 0
    wire [23:0] mode0_txn_addr;
    // data captured in mode 0
    wire [31:0] mode0_txn_data;
    // flag indicating mode0 transaction
    wire mode0_txn_valid_flag_rackclk;
    // in wbclk
    wire mode0_txn_valid_flag_wbclk;
    // pick off the rnw bit
    wire cmd_txn_type = cmd_addr_i[23];
    
    
    // Transaction completed (in both mode 0 and mode 1), wbclk side
    wire txn_done_wbclk;    
    // and in sysclk
    wire txn_done_rackclk;
    // this indicates that the txn_done flag is still propagating
    wire txn_busy_wbclk;
    // this is an upper address bit used for we. It's both a source and a destination.
    (* CUSTOM_CC_SRC = WB_CLK_TYPE, CUSTOM_CC_DST = WB_CLK_TYPE *)
    reg txn_type = 0;
    (* CUSTOM_CC_DST = WB_CLK_TYPE *)
    reg [21:0] wb_address = {22{1'b0}};
    // this is both a destination (mode0, address capture) and source (mode0/1, response data)
    (* CUSTOM_CC_DST = WB_CLK_TYPE, CUSTOM_CC_SRC = WB_CLK_TYPE *)
    reg [31:0] wb_data = {32{1'b0}};
    
    
    // ok, let's just make this work at first
    localparam FSM_BITS = 3;
    localparam [FSM_BITS-1:0] MODE0_IDLE = 0;           // wait for a mode0 transaction
    localparam [FSM_BITS-1:0] MODE1_IDLE = 1;           // wait for a mode1 transaction
    localparam [FSM_BITS-1:0] MODE1_ACK = 2;            // flag the command processor we got the data
    localparam [FSM_BITS-1:0] TXN_WAIT = 3;             // issue a transaction and wait for ack
    localparam [FSM_BITS-1:0] DONE_WBCLK = 4;           // ack received, send the done flag
    localparam [FSM_BITS-1:0] WAIT_DONE_SYSCLK = 5;     // wait for the done flag to propagate
                                                        // the wait here is OK b/c another
                                                        // txn can't come in for a long time in mode0
                                                        // and mode1 waiting is fine
    reg [FSM_BITS-1:0] state = MODE0_IDLE;

    // ok: we don't want to flag clear the reset, that's too iffy.
    // instead, we resample the reset in wb_clk:
    // if the reset is set, and rackclk_ok_i is set and has been set
    // for a while, we assert clear reset.
    // Once the reset clears, we end the clear reset.
    // This SHOULD NOT BE A PROBLEM because rackclk_ok_i toggles SLOWLY.
    // AT LEAST I HOPE.
    (* CUSTOM_CC_DST = WB_CLK_TYPE, ASYNC_REG = "TRUE" *)
    reg [1:0] rackclk_in_reset = {2{1'b0}};
    wire rackclk_ok_delayed;
    (* CUSTOM_CC_SRC = WB_CLK_TYPE *)
    reg rackclk_clear_reset = 1'b0;
    (* CUSTOM_CC_DST = RACKCLK_TYPE, ASYNC_REG = "TRUE" *)
    reg [1:0] rackclk_clear_reset_rackclk = {2{1'b0}};
    SRL16E u_ok_delay(.D(rackclk_ok_i),.CE(1'b1),.CLK(wb_clk_i),
                      .A0(1'b1),.A1(1'b1),.A2(1'b1),.A3(1'b0),
                      .Q(rackclk_ok_delayed));
    // and the reset itself
    wire rackctl_reset;

    assign txn_done_wbclk = (state == DONE_WBCLK);
    
    // the mode transition stuff here is totally and completely wrong, freaking fix it
    always @(posedge wb_clk_i) begin
        rackclk_in_reset <= { rackclk_in_reset[0], rackctl_reset };

        if (!rackclk_ok_i) rackclk_clear_reset <= 0;
        else if (rackclk_ok_delayed) begin
            if (rackclk_in_reset[1]) rackclk_clear_reset <= 1;
            else rackclk_clear_reset <= 0;
        end
        
        // whatever, fix this later
        if (state == MODE0_IDLE && mode_i != MODE0) mode <= MODE1;
        else if (state == MODE1_IDLE && mode_i != MODE1) mode <= MODE0;
    
        if (state == MODE0_IDLE && mode0_txn_valid_flag_wbclk)
            wb_address <= mode0_txn_addr[21:0];
        else if (state == MODE1_IDLE && cmd_valid_i)
            wb_address <= cmd_addr_i[21:0];            

        if (state == MODE0_IDLE && mode0_txn_valid_flag_wbclk)
            txn_type <= mode0_txn_addr[23];
        else if (state == MODE1_IDLE && cmd_valid_i)
            txn_type <= cmd_addr_i[23];            

        // wb_data is used for both reads and writes and
        // we capture it in mode0 every time regardless
        if (state == MODE0_IDLE && mode0_txn_valid_flag_wbclk)
            wb_data <= mode0_txn_data;
        else if (state == MODE1_IDLE && cmd_valid_i)
            wb_data <= cmd_data_i;
        else if (state == TXN_WAIT && wb_ack_i)
            wb_data <= wb_dat_i;               
    
        case (state)
            MODE0_IDLE: if (mode_i != MODE0) state <= MODE1_IDLE;
                        else if (mode0_txn_valid_flag_wbclk) state <= TXN_WAIT;
            TXN_WAIT: if (wb_ack_i || wb_err_i || wb_rty_i) state <= DONE_WBCLK;
            DONE_WBCLK: state <= WAIT_DONE_SYSCLK;
            WAIT_DONE_SYSCLK: if (!txn_busy_wbclk) begin
                if (mode == MODE0) state <= MODE0_IDLE;
                else state <= MODE1_IDLE;
            end
            MODE1_IDLE: if (cmd_valid_i) state <= MODE1_ACK;
            MODE1_ACK: state <= TXN_WAIT;            
        endcase
    end

    always @(posedge rackclk_i) begin    
        // this should always be 0 when we enter reset, assuming that the rackclk_ok_i
        // doesn't go crazy or something.
        rackclk_clear_reset_rackclk <= { rackclk_clear_reset_rackclk[0], rackclk_clear_reset };
    
        if (rackctl_reset) mode_rackclk <= 2'b00;
        else mode_rackclk <= { mode_rackclk[0], mode };
    end
    
    // both a destination (from rackclk_ok_i) and a source (to rackclk_in_reset)
    (* CUSTOM_CC_DST = RACKCLK_TYPE, CUSTOM_CC_SRC = RACKCLK_TYPE *)
    FDPE #(.IS_PRE_INVERTED(1'b1))
         u_rackctl_rst(.C(rackclk_i),.CE(rackclk_clear_reset_rackclk[1]),
                       .D(1'b0),
                       .PRE(rackclk_ok_i),
                       .Q(rackctl_reset));

    // EVERYTHING HERE IS CALLED RXCLK EVEN THOUGH IT'S RACKCLK!!
    rackctl_rxctl_sm_v1 #(.INV(INV),
                          .DEBUG(DEBUG),
                          .RXCLK_TYPE(RACKCLK_TYPE))
        u_rackctl(.rxclk_i(rackclk_i),
                  .rst_i(rackctl_reset),
                  .mode_i(mode_rackclk[1]),
                  .txn_addr_o(mode0_txn_addr),
                  .txn_data_o(mode0_txn_data),
                  .txn_valid_flag_o(mode0_txn_valid_flag_rackclk),
                  .txn_done_flag_i(txn_done_rackclk),
                  .txn_resp_i(wb_data),
                  .mode1_txn_type_i(txn_type),
                  .RACKCTL_P(RACKCTL_P),
                  .RACKCTL_N(RACKCTL_N));

    flag_sync u_mode0_valid_sync(.in_clkA(mode0_txn_valid_flag_rackclk),
                                 .out_clkB(mode0_txn_valid_flag_wbclk),
                                 .clkA(rackclk_i),
                                 .clkB(wb_clk_i));
    flag_sync u_done_sync(.in_clkA(txn_done_wbclk),
                                .out_clkB(txn_done_rackclk),
                                .busy_clkA(txn_busy_wbclk),
                                .clkA(wb_clk_i),
                                .clkB(rackclk_i));    

    assign wb_cyc_o = (state == TXN_WAIT);
    assign wb_stb_o = wb_cyc_o;
    assign wb_adr_o = wb_address;
    assign wb_dat_o = wb_data;
    assign wb_we_o = !txn_type;
    assign wb_sel_o = {4{wb_we_o}};
endmodule
