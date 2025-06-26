`timescale 1ns / 1ps
// buffer and check the command processor stuff
`include "interfaces.vh"
module cmdproc_buffer #(parameter ACLK_TYPE = "NONE",
                        parameter WB_CLK_TYPE = "NONE")(
        input aclk,
        input cmdproc_reset,
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( cmdproc_ , 8 ),
        input cmdproc_tlast,        
        output cmdproc_err_o,
        
        input wb_clk_i,
        output [21:0] cmd_address_o,
        output [31:0] cmd_data_o,
        // this will hold until cleared by ack
        output cmd_valid_o,
        // flag
        input cmd_ack_i
    );
    
    reg [23:0] address = {24{1'b0}};
    reg [31:0] data = {32{1'b0}};
    
    (* CUSTOM_CC_SRC = WB_CLK_TYPE *)
    reg cmdfifo_rst_wbclk = 0;
    (* CUSTOM_CC_DST = ACLK_TYPE, ASYNC_REG = "TRUE" *)
    reg [1:0] cmdfifo_reset = {2{1'b0}};
    always @(posedge aclk) cmdfifo_reset <= {cmdfifo_reset[0], cmdfifo_rst_wbclk};
    `DEFINE_AXI4S_MIN_IF( cmdfifo_ , 8 );
    wire cmdfifo_tlast;
    
    cmd_fifo u_fifo(.s_axis_aclk(aclk),.s_axis_aresetn(!cmdfifo_reset[1]),
                    .m_axis_aclk(wb_clk_i),
                    `CONNECT_AXI4S_MIN_IF( s_axis_ , cmdproc_ ),
                    .s_axis_tlast(cmdproc_tlast),
                    `CONNECT_AXI4S_MIN_IF( m_axis_ , cmdfifo_ ),
                    .m_axis_tlast(cmdfifo_tlast));
    wire cmdproc_reset_wbclk;
    flag_sync u_reset_sync(.in_clkA(cmdproc_reset),.out_clkB(cmdproc_reset_wbclk),
                           .clkA(aclk),.clkB(wb_clk_i));
    
    localparam FSM_BITS = 4;
    localparam [FSM_BITS-1:0] RESET = 0;
    localparam [FSM_BITS-1:0] IDLE = 1;
    localparam [FSM_BITS-1:0] ADDR_1 = 2;
    localparam [FSM_BITS-1:0] ADDR_0 = 3;
    localparam [FSM_BITS-1:0] DATA_3 = 4;
    localparam [FSM_BITS-1:0] DATA_2 = 5;
    localparam [FSM_BITS-1:0] DATA_1 = 6;
    localparam [FSM_BITS-1:0] DATA_0 = 7;
    localparam [FSM_BITS-1:0] ISSUE = 8;
    // STOP PROCESSING, WE ARE BORKED
    localparam [FSM_BITS-1:0] HALT_ERROR = 9;
    (* CUSTOM_CC_SRC = WB_CLK_TYPE *)
    reg [FSM_BITS-1:0] state = RESET;
    
    assign cmdfifo_rst = (state == RESET);
    
    reg reset_seen = 0;    
    wire reset_flag = (state == RESET && !reset_seen);
    wire reset_delay;
    SRLC32E u_rst_delay(.D(reset_flag),.CE(1'b1),.CLK(wb_clk_i),.Q31(reset_delay));
    // cmdproc_reset ONLY jumps us to RESET
    // if we're not waiting for a WB transaction.
    always @(posedge wb_clk_i) begin
        cmdfifo_rst_wbclk <= cmdfifo_rst;
        
        reset_seen <= (state == RESET);
        
        case (state)
            RESET: if (reset_delay) state <= IDLE;
            IDLE: if (cmdproc_reset_wbclk) state <= RESET;
                  else if (cmdfifo_tvalid && cmdfifo_tready) state <= ADDR_1;
            // addr[23:16] is valid in ADDR_1                 
            ADDR_1: if (cmdproc_reset_wbclk) state <= RESET;
                    else if (cmdfifo_tvalid && cmdfifo_tready) state <= ADDR_0;
            // addr[23:8] is valid in ADDR_0 and cmdproc_tdata should have TLAST if addr[23]
            ADDR_0: if (cmdproc_reset_wbclk) state <= RESET;
                    else if (cmdfifo_tvalid && cmdfifo_tready) begin
                        if ((address[23] && !cmdfifo_tlast) ||
                            (!address[23] && cmdfifo_tlast)) state <= HALT_ERROR;
                        else if (address[23]) state <= ISSUE;
                        else state <= DATA_3;
                    end
            // address is totally valid here
            DATA_3: if (cmdproc_reset_wbclk) state <= RESET;
                    else if (cmdfifo_tvalid && cmdfifo_tready) state <= DATA_2;
            // data[31:24] is valid                    
            DATA_2: if (cmdproc_reset_wbclk) state <= RESET;
                    else if (cmdfifo_tvalid && cmdfifo_tready) state <= DATA_1;
            // data[31:16] is valid                    
            DATA_1: if (cmdproc_reset_wbclk) state <= RESET;
                    else if (cmdfifo_tvalid && cmdfifo_tready) state <= DATA_0;
            // data[31:8] is valid and last data is on the bus, TLAST should be set
            DATA_0: if (cmdproc_reset_wbclk) state <= RESET;
                    else if (cmdfifo_tvalid && cmdfifo_tready) begin
                        if (!cmdfifo_tlast) state <= HALT_ERROR;
                        else state <= ISSUE;
                    end
            ISSUE: if (cmd_ack_i) state <= IDLE;
            HALT_ERROR: if (cmdproc_reset_wbclk) state <= RESET;                                                               
        endcase
        if (cmdfifo_tvalid && cmdfifo_tready) begin
            if (state == IDLE) address[23:16] <= cmdfifo_tdata;
            if (state == ADDR_1) address[15:8] <= cmdfifo_tdata;
            if (state == ADDR_0) address[7:0] <= cmdfifo_tdata;
            if (state == DATA_3) data[31:24] <= cmdfifo_tdata;
            if (state == DATA_2) data[23:16] <= cmdfifo_tdata;
            if (state == DATA_1) data[15:8] <= cmdfifo_tdata;
            if (state == DATA_0) data[7:0] <= cmdfifo_tdata;
        end
    end

    assign cmd_valid_o = (state == ISSUE);
    assign cmdproc_err_o = (state == HALT_ERROR);
    
endmodule
