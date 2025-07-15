`timescale 1ns / 1ps
// I cannot figure out what's going on in the uram_event_buffer_v2, so
// I'm abstracting the state machine out.
// aaargh reworked AGAIN because we DO NOT want the stupid address
// to automatically increment, we want it to happen when the marks
// happen!
module uram_event_readout_sm(
        input clk_i,
        input clk_ce_i,        
        input data_available_i,
        output complete_o,
        output [8:0] bram_addr_o,
        output [2:0] bram_en_o,
        output [2:0] casdomux_o,
        output casdomuxen_o,
        output [7:0] channel_en_o,
        output sel_header_o,
        output header_rd_o,
        output valid_o,
        // add the firmware loading crap here
        output [7:0] fw_update_uaddr_o,
        input fw_loading_i,
        input fw_wr_i,
        input [1:0] fw_mark_i,
        output [1:0] fwmon_wr_o
    );
    reg fw_wr_stretch = 0;
    
    // OK: HERE'S THE CORRECT READOUT SEQUENCE
    //
    // This is actually a lot simpler. Again to remember, we functionally have
    // 512 addresses per channel. The bottom 2 bits are laddr, upper 7 bits are
    // uaddr. laddr is embedded in the state.
    //
    // BECAUSE WE'RE IN STANDARD DATA OUT CASCADE, WE NEED TO GO
    //
    // NOTE: casdomux_i can ALSO just be a one-hot shift up, which is probably the way to go
    // 
    // clk  en   addr    casdomux_i  casdomuxen_i    dout_data_phase    dout    ev_tdata    remark
    // 0    000  001     000         0               1                  X       HDR[0]      data_available=1                        IDLE_HEADER0_ADDR1
    // 1    000  002     000         0               0                  X       HDR[0]                                              HEADER1_ADDR2
    // 2    000  002     000         0               1                  X       HDR[0]                                              HEADER1_ADDR2
    // 3    000  003     000         0               0                  X       HDR[1]                                              HEADER2_ADDR3
    // 4    000  003     000         0               1                  X       HDR[1]                                              HEADER2_ADDR3
    // 5    001  000     001         0               0                  X       HDR[2]      RAM READOUT WILL OCCUR                  HEADER3_ADDR0
    // 6    001  000     001         1               1                  X       HDR[2]      RAM IS OK HERE BUT REG NOT CAPTURED     HEADER3_ADDR0
    // 7    001  001     001         0               0                  =       HDR[3]      RAM IS OK HERE BUT REG NOT CAPTURED     DATA0_ADDR1_END
    // 8    001  001     001         0               1                  ARAM[0] HDR[3]      REGCE IS !DOUT_DATA_PHASE - CHECK       DATA0_ADDR1_END
    // 9    001  002     001         0               0                  ARAM[0] ARAM[0]                                             DATA1_ADDR2
    // 10   001  002     001         0               1                  ARAM[1] ARAM[0]                                             DATA1_ADDR2
    // 11   001  003     001         0               0                  ARAM[1] ARAM[1]     LAST RAM READ                           DATA2_ADDR3
    // 12   001  003     001         0               1                  ARAM[2] ARAM[1]                                             DATA2_ADDR3
    // 13   010  000     010         0               0                  ARAM[2] ARAM[2]     NEXT RAM READ WILL OCCUR                DATA3_ADDR0
    // 14   010  000     010         1               1                  ARAM[3] ARAM[2]     RAM OK HERE BUT NOT REGCE               DATA3_ADDR0
    // 15   010  001     010         0               0                  BRAM[X] ARAM[3]     RAM OK HERE BUT NOT REGCE               DATA0_ADDR1_END
    // 16   010  001     010         0               1                  BRAM[0] ARAM[3]     RAM IS NOW OK                           DATA0_ADDR1_END
    // 17   010  002     010         0               0                  BRAM[0] BRAM[0]                                             DATA1_ADDR2
    // 18   010  002     010         0               1                  BRAM[1] BRAM[0]                                             DATA1_ADDR2
    // 19   010  003
    //
    // SO: IDLE_HEADER0 IS ADDR 1
    //     HEADER1      IS ADDR 2
    //     HEADER2      IS ADDR 3
    //     HEADER3      IS ADDR 0
    //     DATA1        
    //     CASDOMUXEN IS ADDR0 && DOUT_DATA_PHASE
    //     CASDOMUX CAN BE EN
    //     EN SHIFT HAPPENS AT DATA2_ADDR3
    //
    // NOTE: WE CAN SET COMPLETE AT DATA2_ADDR3
    localparam FSM_BITS = 4;
    localparam [FSM_BITS-1:0] HEADER0                   = 5;  // 5
    localparam [FSM_BITS-1:0] HEADER1                   = 6;  // 6
    localparam [FSM_BITS-1:0] HEADER2                   = 7;  // 7
    localparam [FSM_BITS-1:0] HEADER3                   = 4;  // 4
    localparam [FSM_BITS-1:0] DATA0                     = 1;  // 1
    localparam [FSM_BITS-1:0] DATA1                     = 2;  // 2
    localparam [FSM_BITS-1:0] DATA2                     = 3;  // 3
    localparam [FSM_BITS-1:0] DATA3                     = 0;  // 0
    localparam [FSM_BITS-1:0] FW0                       = 8;  // 8
    localparam [FSM_BITS-1:0] FW1                       = 9;  // 9
    localparam [FSM_BITS-1:0] FW2                       = 10;  // 10
    localparam [FSM_BITS-1:0] FW3                       = 11;  // 11
    (* CUSTOM_MC_DST_TAG = "FW_VALID", FSM_ENCODING = "user_encoding" *)
    reg [FSM_BITS-1:0] state = HEADER0;
    (* CUSTOM_MC_DST_TAG = "FW_VALID" *)
    reg [6:0] bram_uaddr = {7{1'b0}};
    wire [7:0] bram_uaddr_next = bram_uaddr + 1;

    reg [1:0] fwmon_wr = {2{1'b0}};
    
    
    reg [2:0] active_bram = {3{1'b0}};
    reg [7:0] active_chan = {8{1'b0}};

    reg valid = 0;

    reg channel_complete = 0;
    reg readout_complete = 0;
    // combine this with fw_loading_i
    wire activate_any_channel = data_available_i || fw_loading_i;
    // part 1: this indicates when we actually increment the address
    wire fw_advance_address = (fw_wr_i || fw_wr_stretch) && clk_ce_i && (state[1:0] == 2'b11);
    // part 2. we use the carry-chain to as the 6 bit compare for bram_uaddr:
    wire fw_uaddr_advance = fw_advance_address && bram_uaddr_next[7];
    // indicates when we advance uaddr
    wire advance_address = (state == DATA2 && active_bram[2] && clk_ce_i) || (fw_loading_i && fw_advance_address);   
    
    reg mark_reset = 0;
    
    // NOTE NOTE NOTE NOTE NOTE NOTE NOTE
    // YOU ALWAYS HAVE TO TRANSFER AT LEAST 4 BYTES EACH TIME,
    // YOU CAN'T DO 3 BYTES THEN MARK    
    always @(posedge clk_i) begin
        if (clk_ce_i) fw_wr_stretch <= 0;
        else if (fw_wr_i) fw_wr_stretch <= 1;

        if (|fw_mark_i) mark_reset <= 1;
        else if (clk_ce_i) mark_reset <= 0;
    
        if (clk_ce_i) begin
            case (state)
                HEADER0: if (fw_loading_i) state <= FW0;
                         else if (data_available_i) state <= HEADER1;
                HEADER1: state <= HEADER2;
                HEADER2: state <= HEADER3;
                HEADER3: state <= DATA0;
                DATA0: if (readout_complete) state <= HEADER0;
                       else state <= DATA1;
                DATA1: state <= DATA2;
                DATA2: state <= DATA3;
                DATA3: state <= DATA0;
                FW0: if (!fw_loading_i) state <= HEADER0;
                     else if (fw_wr_i || fw_wr_stretch) state <= FW1;
                FW1: if (!fw_loading_i) state <= HEADER0;
                     else if (fw_wr_i || fw_wr_stretch) state <= FW2;
                FW2: if (!fw_loading_i) state <= HEADER0;
                     else if (fw_wr_i || fw_wr_stretch) state <= FW3;
                FW3: if (!fw_loading_i) state <= HEADER0;
                     else if (fw_wr_i || fw_wr_stretch) state <= FW0;               
            endcase
        end                        
        // valid
        if (clk_ce_i) begin
            if (state == HEADER0 && data_available_i) valid <= 1;
            else if (state == DATA0 && readout_complete) valid <= 0;
        end
        
        // channel completion
        if (clk_ce_i)
            channel_complete <= active_bram[2] && bram_addr_o == 9'h1FF;
        // readout completion. not a flag yet b/c of clk_ce_i.
        if (clk_ce_i) begin
            if (state == DATA0 || state == HEADER0) readout_complete <= 0;
            else if (active_bram[2] && bram_addr_o == 9'h1FF && active_chan[7]) readout_complete <= 1;
        end                        

        // active bram shift
        if (clk_ce_i) begin
            if (state == HEADER0) active_bram <= 3'b001;
            else if (state == DATA2) active_bram <= { active_bram[1:0], active_bram[2] };
        end
        // active channel shift. we have to swap one clock earlier.
        if (state == HEADER0 && clk_ce_i) active_chan <= { {7{1'b0}}, activate_any_channel };
        else if (channel_complete && !clk_ce_i) active_chan <= { active_chan[6:0], 1'b0 };
        
        if (state == HEADER0 || mark_reset) bram_uaddr <= {7{1'b0}};
        else if (advance_address) bram_uaddr <= bram_uaddr_next;
        
        fwmon_wr[0] <= fw_wr_i && !fw_update_uaddr_o[7];
        fwmon_wr[1] <= fw_wr_i && fw_update_uaddr_o[7];
    end        

    // we moved the fwupd uaddr calc to its own module
    // technically this MIGHT be simplify-able even more: who knows
    fwupd_uaddr u_fwuaddr(.clk_i(clk_i),
                          .ce_i(fw_uaddr_advance),
                          .bank_ce_i(fw_mark_i),
                          .rstb_i(fw_loading_i),
                          .uaddr_o(fw_update_uaddr_o));

    // readout_complete goes high in DATA3 and stays there through DATA0.
    // we need to make the output a flag, and do it early so that the read buffer
    // can advance and data_available can go low.
    assign complete_o = readout_complete && (state == DATA3) && clk_ce_i;
    assign bram_addr_o = { bram_uaddr, state[1:0] };
    assign bram_en_o = active_bram;
    assign casdomux_o = ~active_bram;
    assign casdomuxen_o = (state == HEADER3 || state == DATA3) && clk_ce_i;
    assign channel_en_o = active_chan;
    assign sel_header_o = state[2];
    assign header_rd_o = (state == HEADER3) && clk_ce_i;    
    assign valid_o = valid;
    assign fwmon_wr_o = fwmon_wr;
    
endmodule
