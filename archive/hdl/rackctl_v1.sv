`timescale 1ns / 1ps
`include "interfaces.vh"
// This is the RACKctl handler. Based on the original bidir testing.
// implements both mode 0 and mode 1.
module rackctl_v1 #(parameter INV=1'b0)(
        input wb_clk_i,
        input rxclk_i,
        input rxclk_ok_i,
        // sigh, I feel like I need a better way to do this.
        `HOST_NAMED_PORTS_WB_IF( wb_ , 22, 32 ),        
        // this is the CIN path data in mode 1.
        // it comes in on sysclk, and crosses to wbclk in a FIFO.
        input aclk,
        input aresetn,
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( cin_ , 24),                
        inout RACKCTL_P,
        inout RACKCTL_N
    );
    
    reg rackctl_mode = 0;
    wire rackctl_do_txn_rxclk = (state == MODE0_ISSUE_TXN);
    wire rackctl_do_txn_wbclk;    
    wire rackctl_txn_done_wbclk;
    wire rackctl_txn_done_rxclk;
    
    always @(posedge rxclk_i) begin
        // turnaround timer does not need a reset
        if (state == MODE0_TURNAROUND_0 || state == MODE0_TURNAROUND_1) 
            turnaround_timer <= turnaround_timer[6:0] + 1;
        else
            turnaround_timer <= {7{1'b0}};
    
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
