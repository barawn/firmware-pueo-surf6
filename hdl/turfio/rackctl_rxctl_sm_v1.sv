`timescale 1ns / 1ps
// This is the rxclk-side state machine for the v1 rackctl.
// For testing you can also just set mode to 0,
// and loop (txn_valid_flag_o && txn_addr_o[23]) to txn_done_flag_i and
// put some fixed value in txn_resp_i.
// rst_i should be set when rxclk_ok_i goes low and then cleared a few clocks later.
module rackctl_rxctl_sm_v1 #(parameter INV=1'b0,
                             parameter DEBUG="FALSE")(
        // rxclk input
        input rxclk_i,
        // sync reset
        input rst_i,
        // mode state
        input mode_i,                
        // received data
        output [23:0] txn_addr_o,
        output [31:0] txn_data_o,
        // indicates that a transaction has occured in mode 0
        output        txn_valid_flag_o,
        // this indicates a transaction is complete in both mode0/mode1
        input         txn_done_flag_i,
        // this is the data to output in both mode0 and mode1
        input [31:0]  txn_resp_i,
        // if 0, this is a write and just needs an ack.
        input         mode1_txn_type_i,
                
        inout RACKCTL_P,
        inout RACKCTL_N
    );
    // mode 0 preamble
    localparam [4:0] MODE0_PREAMBLE = 5'b10101;
    // postamble both in mode 0 and 1
    localparam [3:0] POSTAMBLE = 4'b1110;

    // data coming FROM IOB
    wire rackctl_in;
    // MONITOR data coming from IOB, inverted
    wire rackctl_in_inv;
    // tristate the IOB    
    wire rackctl_tri;
    // data going TO IOB
    wire rackctl_out;
    generate
        if (INV == 1'b1) begin : IOINV            
            IOBUFDS_DIFF_OUT u_iob(.I(rackctl_out),.O(rackctl_in_inv),.OB(rackctl_in),.TM(rackctl_tri),.TS(rackctl_tri),
                                   .IO(RACKCTL_N),
                                   .IOB(RACKCTL_P));
        end else begin : IO
            IOBUFDS_DIFF_OUT u_iob(.I(rackctl_out),.O(rackctl_in),.OB(rackctl_in_inv),.TM(rackctl_tri),.TS(rackctl_tri),
                                   .IO(RACKCTL_P),
                                   .IOB(RACKCTL_N));
        end
    endgenerate        
    
    // at 125 MHz, we need to delay around 125 clocks once we hit turnaround.
    // just use 128.
    reg [7:0] turnaround_timer = {8{1'b0}};
    
    (* IOB = "TRUE", CUSTOM_IGN_DST = "RXCLK" *)
    reg rackctl_in_ff = 0;
    reg rackctl_in_ff_rereg = 0;
    (* IOB = "TRUE", CUSTOM_IGN_DST = "RXCLK" *)
    reg rackctl_mon_ff = 0;
    // this is both the input AND output shift register.
    // Unlike the bidir tests, we don't use the direct input.
    reg [31:0] data_capture = {31{1'b0}};
    // this is the address capture. it grabs from data_capture when exiting.
    reg [23:0] txn_capture = {24{1'b0}};
    
    // Note: we idle at 1, so the preamble is technically just 0101.
    // The TURFIO side needs to insert an additional 1 in the preamble
    // to ensure that we kick off at IDLE after a turnaround.
    //
    // The postamble of 1110 is just intended to ensure there are enough 1s after the turnaround
    // so the zero (a start bit) will be an indicator. When we replace this with the actual
    // interface, the 1s will just be an idle.
//    localparam FSM_BITS = 4;
//    localparam [FSM_BITS-1:0] IDLE = 0;         // check 10
//    localparam [FSM_BITS-1:0] PREAMBLE_0 = 1;   // check 1
//    localparam [FSM_BITS-1:0] PREAMBLE_1 = 2;   // check 0
//    localparam [FSM_BITS-1:0] PREAMBLE_2 = 3;   // check 1
//    localparam [FSM_BITS-1:0] DATA = 4;
//    localparam [FSM_BITS-1:0] TURNAROUND_0 = 5;
//    localparam [FSM_BITS-1:0] POSTAMBLE_0 = 6; // output 1
//    localparam [FSM_BITS-1:0] POSTAMBLE_1 = 7; // output 1
//    localparam [FSM_BITS-1:0] POSTAMBLE_2 = 8; // output 1
//    localparam [FSM_BITS-1:0] POSTAMBLE_3 = 9; // output 0
//    localparam [FSM_BITS-1:0] ECHO = 10;
//    localparam [FSM_BITS-1:0] TURNAROUND_1 = 11;
//    reg [FSM_BITS-1:0] state = IDLE;
    localparam FSM_BITS = 4;
    localparam [FSM_BITS-1:0] RESET = 0;            // reset
    localparam [FSM_BITS-1:0] MODE0_IDLE = 1;       // check 10
    localparam [FSM_BITS-1:0] MODE0_PREAMBLE_0 = 2; // check 1
    localparam [FSM_BITS-1:0] MODE0_PREAMBLE_1 = 3; // check 0
    localparam [FSM_BITS-1:0] MODE0_PREAMBLE_2 = 4; // check 1
    localparam [FSM_BITS-1:0] MODE0_TXN        = 5; // capture 24 bits
    localparam [FSM_BITS-1:0] MODE0_DATA       = 6; // capture 32 bits
    localparam [FSM_BITS-1:0] MODE0_ISSUE_TXN  = 7; // issue transaction
    localparam [FSM_BITS-1:0] MODE0_TURNAROUND_0=8; // switch from receive to transmit
    localparam [FSM_BITS-1:0] POSTAMBLE_0=9;        // output 1
    localparam [FSM_BITS-1:0] POSTAMBLE_1=10;       // output 1
    localparam [FSM_BITS-1:0] POSTAMBLE_2=11;        // output 1
    localparam [FSM_BITS-1:0] POSTAMBLE_3=12;       // output 0
    localparam [FSM_BITS-1:0] RESPONSE=13;          // output data
    localparam [FSM_BITS-1:0] MODE0_TURNAROUND_1=14;// switch from transmit to receive
    localparam [FSM_BITS-1:0] MODE1_IDLE = 15;      // wait for input on cin
    reg [FSM_BITS-1:0] state = RESET;

    // data counter
    reg [5:0]   data_counter = {6{1'b0}};
    // what we add to data counter each time. see cleverness below
    wire [3:0]  data_counter_addend = { (state == MODE0_PREAMBLE_2), 1'b0, 1'b0, 1'b1 };
    // data counter gets added in MODE0_PREAMBLE_2, DATA, POSTAMBLE_3, and RESPONSE.
    // The extra count in POSTAMBLE_3 doesn't matter, it flips back to 0 once it's out of the state.
    
    // this is what we drive when we're not driving data
    wire postamble_data = (state == MODE0_TURNAROUND_0 || state == POSTAMBLE_0 || 
                           state == POSTAMBLE_1 || state == MODE1_IDLE);
    
    // IOB controls    
    // this is called drive_rackctl_b because it's the T input (so if 1 = tristate)
    (* KEEP = "TRUE", IOB = "TRUE", CUSTOM_IGN_SRC = "RXCLK" *)
    reg drive_rackctl_b = 1;
    // this is drive_rackctl_mon because it's NOT inverted
    (* KEEP = "TRUE" *)
    reg drive_rackctl_mon = 0;
    assign rackctl_tri = drive_rackctl_b;
    (* IOB = "TRUE" *)
    reg rackctl_out_ff = 0;
    assign rackctl_out = rackctl_out_ff;
    
    reg rackctl_mode = 0;
    reg mode1_txn_type = 0;
            
    // ok so in MODE0_TXN it needs to work this way. Imagine if it was 3 4-bit words instead of 8-bit.
    // Note the ultra-sleaze: we program this as an adder, where if the state is MODE0_PREAMBLE_2
    // it adds the word width + 1, otherwise it adds 1.
    // clk  state               rackctl_in_ff   data_capture    txn_capture     data_counter
    // 0    MODE0_PREAMBLE_2    1               0               X               0
    // 1    MODE0_TXN           C3              0               X               5
    // 2    MODE0_TXN           C2              C3              X               6           
    // 3    MODE0_TXN           C1              C32             X               7
    // 4    MODE0_TXN           C0              C321            X               8
    // 5    MODE0_TXN           B3              C3210           X               9
    // 6    MODE0_TXN           B2              C3210B3         X               10
    // 7    MODE0_TXN           B1              C3210B32        X               11
    // 8    MODE0_TXN           B0              C3210B321       X               12
    // 9    MODE0_TXN           A3              C3210B3210      X               13
    // 10   MODE0_TXN           A2              C3210B3210A3    X               14
    // 11   MODE0_TXN           A1              C3210B3210A32   X               15
    // 12   MODE0_TXN           A0              C3210B3210A321  X               16
    // Then when it rolls over (data_counter[5] in the real 8-bit case)
    // you check data_capture[22] (since it hasn't finished yet) to determine if you keep going or
    // jump to turnaround.
    // The transaction data grabs {data_capture[22:0],rackctl_in_ff} as the transaction store.
    // Once it rolls over if you're in MODE0_DATA, it will fully capture because the rollover
    // just continues to 1. If you imagine an 8-bit datapath, you have
    // 0    MODE0_TXN           A0              C3210B3210A321  X               16
    // 1    MODE0_DATA          D7              C3210B3210A3210 C3210B3210A3210 1
    // 2    MODE0_DATA          D6              D7              C3210B3210A3210 2
    // 3    MODE0_DATA          D5              D76             C3210B3210A3210 3
    // 4    MODE0_DATA          D4              D765            C3210B3210A3210 4
    // 5    MODE0_DATA          D3              D7654           C3210B3210A3210 5
    // 6    MODE0_DATA          D2              D76543          C3210B3210A3210 6
    // 7    MODE0_DATA          D1              D765432         C3210B3210A3210 7
    // 8    MODE0_DATA          D0              D7654321        C3210B3210A3210 8
    // 9    MODE0_ISSUE_TXN     X               D76543210       C3210B3210A4320 X
    // (again this is just an example, the counter will properly roll to data_counter[5] in both cases)
    always @(posedge rxclk_i) begin
        if (rst_i) mode1_txn_type <= 1'b0;
        else begin
            if (state == MODE0_IDLE && mode_i) mode1_txn_type <= 1'b0;
            else if (state == MODE1_IDLE && txn_done_flag_i) mode1_txn_type <= mode1_txn_type_i;
        end
        
        if (rst_i) rackctl_mode <= 0;
        else if (state == MODE0_IDLE && mode_i) rackctl_mode <= 1;

        rackctl_in_ff <= rackctl_in;
        rackctl_in_ff_rereg <= rackctl_in_ff;

        rackctl_mon_ff <= rackctl_in_inv;

        // state machine needs a reset
        if (rst_i) state <= RESET;
        else begin
            case (state)
                RESET: state <= MODE0_IDLE;
                MODE0_IDLE: if (mode_i) state <= MODE0_TURNAROUND_0;
                            else if (!rackctl_in_ff && rackctl_in_ff_rereg) state <= MODE0_PREAMBLE_0;
                MODE0_PREAMBLE_0: if (rackctl_in_ff == MODE0_PREAMBLE[2]) state <= MODE0_PREAMBLE_1; else state <= MODE0_IDLE;
                MODE0_PREAMBLE_1: if (rackctl_in_ff == MODE0_PREAMBLE[3]) state <= MODE0_PREAMBLE_2; else state <= MODE0_IDLE;
                MODE0_PREAMBLE_2: if (rackctl_in_ff == MODE0_PREAMBLE[4]) state <= MODE0_TXN; else state <= MODE0_IDLE;
                MODE0_TXN: if (data_counter[5]) begin
                    if (!data_capture[22]) state <= MODE0_DATA;
                    else state <= MODE0_ISSUE_TXN;                    
                end
                MODE0_DATA: if (data_counter[5]) state <= MODE0_ISSUE_TXN;
                MODE0_ISSUE_TXN: state <= MODE0_TURNAROUND_0;
                MODE0_TURNAROUND_0: if (turnaround_timer[7]) state <= POSTAMBLE_0;
                POSTAMBLE_0: state <= POSTAMBLE_1;
                POSTAMBLE_1: state <= POSTAMBLE_2;
                POSTAMBLE_2: state <= POSTAMBLE_3;
                POSTAMBLE_3: if ((rackctl_mode == 1'b1 && !mode1_txn_type)) state <= MODE1_IDLE;
                             else if (!txn_capture[23]) state <= MODE0_TURNAROUND_1;
                             else state <= RESPONSE;
                RESPONSE: if (data_counter[5]) begin
                    if (rackctl_mode == 1'b1) state <= MODE1_IDLE;
                    else state <= MODE0_TURNAROUND_1;
                end
                MODE0_TURNAROUND_1: if (turnaround_timer[7]) state <= MODE0_IDLE;
                MODE1_IDLE: if (txn_done_flag_i) state <= POSTAMBLE_0;
            endcase
        end
        // tristate on reset        
        if (state == RESET) begin
            drive_rackctl_b <= 1'b1;
            drive_rackctl_mon <= 1'b0;                  
        end else begin
            // drive in mode 1 or entering turnaround
            if ((state == MODE0_IDLE && mode_i) || state == MODE0_TURNAROUND_0) begin
                drive_rackctl_b = 1'b0;
                drive_rackctl_mon <= 1'b1;
            end else if (state == MODE0_TURNAROUND_1) begin
                drive_rackctl_b <= 1'b1;
                drive_rackctl_mon <= 1'b0;
            end 
        end                   
        // no reset needed. this could be improved since it's just a delay
        if (state == MODE0_TURNAROUND_0 || state == MODE0_TURNAROUND_1)
            turnaround_timer <= turnaround_timer[6:0] + 1;
        else
            turnaround_timer <= {7{1'b0}};
        // no reset needed, it'll reset in the reset state
        // data counter gets added in MODE0_PREAMBLE_2, MODE0_TXN, MODE0_DATA, POSTAMBLE_3, and RESPONSE.
        if (state == MODE0_PREAMBLE_2 || state == MODE0_TXN || state == MODE0_DATA || 
            state == POSTAMBLE_3 || state == RESPONSE)
            data_counter <= data_counter[4:0] + data_counter_addend[3:0];
        else
            data_counter <= {5{1'b0}};

        // data capture is just a loadable shift register
        // it shifts up during MODE0_TXN, MODE0_DATA, and RESPONSE. It loads when a txn is done.
        // We also have to shift in POSTAMBLE_3 because rackctl_out_ff grabs data_capture[31]
        // there.
        if (txn_done_flag_i) 
            data_capture <= txn_resp_i;
        else if (state == MODE0_TXN || state == MODE0_DATA || state == RESPONSE || state == POSTAMBLE_3)
            data_capture <= { data_capture[30:0], rackctl_in_ff };
            
        // txn_capture grabs off of data_capture when data_counter[5]. it has to grab rackctl_in_ff too
        if (state == MODE0_TXN && data_counter[5]) txn_capture <= { data_capture[22:0], rackctl_in_ff };
        
        // and the output is either the postamble or the top bit
        // we have to invert because there's no optional inverter between us and the IOB
        rackctl_out_ff <= INV ^ ((state == RESPONSE || state == POSTAMBLE_3) ? data_capture[31] : postamble_data);
    end

    // the rackctl ILA takes
    // 1, 32, 1, 4, 6
    // rackctl_mon_ff
    // data_capture
    // drive_rackctl_mon
    // state
    // data_counter
    generate
        if (DEBUG == "TRUE") begin
            rackctl_ila u_ila(.clk(rxclk_i),
                              .probe0(rackctl_mon_ff),
                              .probe1(data_capture),
                              .probe2(drive_rackctl_mon),
                              .probe3(state),
                              .probe4(data_counter));
        end
    endgenerate
    assign txn_addr_o = txn_capture;
    assign txn_data_o = data_capture;
    assign txn_valid_flag_o = (state == MODE0_ISSUE_TXN);
    
endmodule
