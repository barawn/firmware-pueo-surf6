`timescale 1ns / 1ps
// The bidir test module is designed to allow us to test how easily we can do the
// bidirectional LVDS commanding.
//
// Bidirectional LVDS sucks because the tristate time on an UltraScale is just utterly
// batshit ridiculous (roughly 1 microsecond). But if you consider this compared to
// a serial interface, it's still ludicrously faster.
//
// In addition we'll probably add a way to transition this to dedicated transmit
// or something so that it becomes the pure response path. I don't know. Still need
// to work on this.
//
// If we run off of RXCLK, we can guarantee the capture timing. We'll need to be
// a bit generous on the turnaround timing.
module turfio_bidir_test #(parameter INV=1'b0)(
        input rxclk_i,
        inout RACKCTL_P,
        inout RACKCTL_N
    );
    
    localparam [4:0] PREAMBLE = 5'b10101;
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
    // this is just for testing
    reg [30:0] data_capture = {31{1'b0}};
    // this goes to the ILA
    wire [31:0] full_data = { data_capture, rackctl_in_ff };
    reg [5:0] data_counter = {6{1'b0}};
    
    // Note: we idle at 1, so the preamble is technically just 0101.
    // The TURFIO side needs to insert an additional 1 in the preamble
    // to ensure that we kick off at IDLE after a turnaround.
    //
    // The postamble of 1110 is just intended to ensure there are enough 1s after the turnaround
    // so the zero (a start bit) will be an indicator. When we replace this with the actual
    // interface, the 1s will just be an idle.
    localparam FSM_BITS = 4;
    localparam [FSM_BITS-1:0] IDLE = 0;         // check 10
    localparam [FSM_BITS-1:0] PREAMBLE_0 = 1;   // check 1
    localparam [FSM_BITS-1:0] PREAMBLE_1 = 2;   // check 0
    localparam [FSM_BITS-1:0] PREAMBLE_2 = 3;   // check 1
    localparam [FSM_BITS-1:0] DATA = 4;
    localparam [FSM_BITS-1:0] TURNAROUND_0 = 5;
    localparam [FSM_BITS-1:0] POSTAMBLE_0 = 6; // output 1
    localparam [FSM_BITS-1:0] POSTAMBLE_1 = 7; // output 1
    localparam [FSM_BITS-1:0] POSTAMBLE_2 = 8; // output 1
    localparam [FSM_BITS-1:0] POSTAMBLE_3 = 9; // output 0
    localparam [FSM_BITS-1:0] ECHO = 10;
    localparam [FSM_BITS-1:0] TURNAROUND_1 = 11;
    reg [FSM_BITS-1:0] state = IDLE;

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
    
    wire postamble_data = (state == TURNAROUND_0 || state == POSTAMBLE_0 || state == POSTAMBLE_1);
    always @(posedge rxclk_i) begin
        if (state == TURNAROUND_0 || state == TURNAROUND_1) turnaround_timer <= turnaround_timer[6:0] + 1;
        else turnaround_timer <= {7{1'b0}};
    
        // ONLY GO THROUGH rackctl_in_ff to avoid the dependency on the tristate reg
        // I can't just check the preamble like this, sigh.
        // Instead I need to reregister rackctl_in_ff and look for a falling edge to start the preamble search.
        // The overall preamble sequence is 10101, so once we see a falling edge we only need 3 more checks
        // clk  rackctl_in_ff   rackctl_in_ff_rereg     counter     data_reg    state
        // 0    1               1                       0           X X X       IDLE
        // 1    1               1                       0           X X X       IDLE
        // 2    0               1                       0           X X X       IDLE        (if (!rackctl_in_ff && rackctl_in_ff_rereg) state <= PREAMBLE_0)
        // 3    1               0                       0           X X X       PREAMBLE_0  if rackctl_in_ff state <= PREAMBLE_1
        // 4    0               1                       0           X X X       PREAMBLE_1  if !rackctl_in_ff state <= PREAMBLE_2
        // 5    1               0                       1           X X X       PREAMBLE_2  if rackctl_in_ff state <= DATA
        // 6    D[3]            1                       2           X X X       DATA
        // 7    D[2]            D[3]                    3           X X D3      DATA
        // 8    D[1]            D[2]                    4           X D3D2      DATA
        // 9    D[0]            D[1]                    0           D3D2D1      TURNAROUND_0
        // The reason for this is that the input FF is already captured at each step. We STOP once we enter TURNAROUND_0.
        // Now watch ECHO.
        //                                                                                      rackctl_out_ff
        // 0    D[0]            D[0]                    0           D3D2D1      TURNAROUND_0    1
        // 1    D[0]            D[0]                    0           D3D2D1      POSTAMBLE_0     1
        // 2    D[0]            D[0]                    0           D3D2D1      POSTAMBLE_1     1
        // 3    D[0]            D[0]                    0           D3D2D1      POSTAMBLE_2     1
        // 4    D[0]            D[0]                    0           D3D2D1      POSTAMBLE_3     0
        // 5    D[0]            D[0]                    1           D2D1D0      ECHO            D3
        // 6    D[0]            D[0]                    2           D1D0D0      ECHO            D2
        // 7    D[0]            D[0]                    3           D0D0D0      ECHO            D1
        // 8    D[0]            D[0]                    4           D0D0D0      ECHO            D0
        //
        // So our count logic is if (state == PREAMBLE_1 || state == PREAMBLE_2 || state == POSTAMBLE_3 || state == DATA || state == ECHO)
        // else 0.
        if (state == PREAMBLE_1 || state == PREAMBLE_2 || state == POSTAMBLE_3 || state == DATA || state == ECHO) 
            data_counter <= data_counter[4:0] + 1;
        else
            data_counter <= 6'd0;

        rackctl_in_ff_rereg <= rackctl_in_ff;

        case (state)
            IDLE: if (!rackctl_in_ff && rackctl_in_ff_rereg) state <= PREAMBLE_0;
            PREAMBLE_0: if (rackctl_in_ff == PREAMBLE[2]) state <= PREAMBLE_1; else state <= IDLE;
            PREAMBLE_1: if (rackctl_in_ff == PREAMBLE[3]) state <= PREAMBLE_2; else state <= IDLE;
            PREAMBLE_2: if (rackctl_in_ff == PREAMBLE[4]) state <= DATA; else state <= IDLE;
            DATA: if (data_counter[5]) state <= TURNAROUND_0;
            TURNAROUND_0: if (turnaround_timer[7]) state <= POSTAMBLE_0; // postamble_data = 1 rackctl_out_ff = X - we DO NOT DRIVE in TURNAROUND_0
            POSTAMBLE_0: state <= POSTAMBLE_1;  // postamble_data = 1 rackctl_out_ff = 1
            POSTAMBLE_1: state <= POSTAMBLE_2;  // postamble_data = 1 rackctl_out_ff = 1
            POSTAMBLE_2: state <= POSTAMBLE_3;  // postamble_data = 0 rackctl_out_ff = 1
            POSTAMBLE_3: state <= ECHO;         // postamble_data = d[31] rackctl_out_ff = 0
            ECHO: if (data_counter[5]) state <= TURNAROUND_1;
            TURNAROUND_1: if (turnaround_timer[7]) state <= IDLE;    // we DO drive in TURNAROUND_1
       endcase

       rackctl_mon_ff <= rackctl_in_inv;

       // we sample so long as we're through data
       if (state == IDLE || state == PREAMBLE_0 || state == PREAMBLE_1 || 
           state == PREAMBLE_2|| state == DATA) begin
           rackctl_in_ff <= rackctl_in;
       end       
       // we shift if we're in data or echo
       if (state == DATA || state == ECHO) begin
            data_capture <= { data_capture[29:0], rackctl_in_ff };
       end            
       
       if (state == TURNAROUND_0) begin
            drive_rackctl_b <= 0;
            drive_rackctl_mon <= 1;
       end else if (state == TURNAROUND_1) begin
            drive_rackctl_b <= 1;
            drive_rackctl_mon <= 0;
       end
       // invert here because there's no optional inverter between us and the IOB
       rackctl_out_ff <= INV ^ ((state == ECHO || state == POSTAMBLE_3) ? data_capture[30] : postamble_data);
    end

    rackctl_ila u_ila(.clk(rxclk_i),
                      .probe0(rackctl_mon_ff),
                      .probe1(full_data),
                      .probe2(drive_rackctl_mon),
                      .probe3(state),
                      .probe4(data_counter));
            
endmodule
