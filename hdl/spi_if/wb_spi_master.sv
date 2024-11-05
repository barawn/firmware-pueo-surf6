`timescale 1ns / 1ps
// go from SPI->WISHBONE
// the assumption here is that the local busses are waaay faster than SPI:
// we just do
// <20-bit address+rnw+3 dummy bits> <32-bit data in/out>
// The dummy bits aren't completely dummy. We abscond with 2 of them to
// allow for 16 bit accesses to handle the RFDC in a "more magic appropriate"
// way. DUMMY1 is upper write disable, DUMMY2 is lower write disable.
// Stupidly the RFDC shit, while it does do 16-bit writes, only ever does
// them on aligned boundaries, so really DUMMY1 is only ever going to be set.
// Thankfully it only does 16 bit stuff so be happy!!!
// We can do this because the 22-bit interface is 32-bits so the bottom 2 bits are
// always zero.
//
// the 'default' bit order under linux (the one you don't need a bit flag set for)
// is MSB first, so we use that.
// This means we shift UP everywhere: IN the LSB, OUT the MSB
// note that for writes, MOSI will shift out the input data because that's the way the logic works
`include "interfaces.vh"
module wb_spi_master #(parameter WB_CLK_TYPE="NONE",
                       parameter DEBUG = "TRUE")(
        input spi_cclk_i,
        input spi_mosi_i,
        input spi_cs_i,
        output spi_miso_o,
        input wb_clk_i,
        input wb_rst_i,
        `HOST_NAMED_PORTS_WB_IF( wb_ , 22, 32 )
    );
    
    reg [19:0] spi_addr_hold = {20{1'b0}};
    reg spi_rnw_hold = 0;
    reg [31:0] spi_shift_reg = {32{1'b0}};    
    reg [1:0] spi_cclk_sync = {2{1'b0}};
    reg [1:0] spi_cs_sync = {2{1'b0}};
    reg [1:0] spi_mosi_sync = {2{1'b0}};
    
    // set when the wishbone path begins, cleared when we get the ack
    reg wb_cycle = 0;
    // 16-bit write disables
    reg [1:0] word_write_disable = {2{1'b0}};
    // set at address_cycle and cleared 2 clocks later.
    reg dummy_clocks = 0;
    // don't need a counter, just a single bit will do
    reg dummy_clocks_rereg = 0;
    wire spi_cclk_rflag = spi_cclk_sync[0] && !spi_cclk_sync[1] && !spi_cs_sync[1];
           
    wire spi_cclk_shift = spi_cclk_rflag && !dummy_clocks;
    // our full sequence is 24+32=56 bits, but we use a 7-bit counter so we can just 
    // guard against rollover with 1 bit. Everything else just qualifies on the 6-bit
    // value.
    reg [6:0] spi_counter = {7{1'b0}};
    wire [5:0] spi_stage = spi_counter[5:0];
    
    // TODO:
    // there are probably better ways to do this. if we add an additional bit to our
    // counter (8 bits) we eliminate the double-detect here by embedding it in the
    // add logic.
    // long to prevent an overflow, so we could actually do:
    // 1. start at 43, detect 01x_xxxx (happens 21 clocks later)
    //    when this happens, add 30 instead of 1 (so we go 010_0000 => 101_1110)
    //    then a rising edge on spi_counter[7] would be data_cycle_stage.
    // need to think about this.
    wire address_cycle_stage = (spi_stage == 21);
    wire data_cycle_stage = (spi_stage == 55);
        
    // ok: the way this works is that the SPI shift register just keeps spinning,
    // and spi_addr_hold AND spi_rnw grabs their value at the correct time.
    // because it's a shift register, we can just grab this wherever - if we grab it
    // at 21, the data on spi_mosi is DUMMY0, and the data on spi_shift_reg[0] is
    // spi_rnw.
    //    
    // spi_counter function
    // 0           ADDR[19]
    // 1           ADDR[18]
    // 2           ADDR[17]
    // 3           ADDR[16]
    // 4           ADDR[15]
    // 5           ADDR[14]
    // 6           ADDR[13]
    // 7           ADDR[12]
    // 8           ADDR[11]
    // 9           ADDR[10]
    // 10          ADDR[09]
    // 11          ADDR[08]
    // 12          ADDR[07]
    // 13          ADDR[06]
    // 14          ADDR[05]
    // 15          ADDR[04]
    // 16          ADDR[03]
    // 17          ADDR[02]
    // 18          ADDR[01]
    // 19          ADDR[00]
    // 20          READ_NOT_WRITE
    // 21          DUMMY0           -   addr_hold and spi_rnw can grab from shift_reg here
    //                                  wb_cycle can set on (spi_counter == 21 && shift_reg[0]) || (spi_counter == 55 && !spi_rnw)
    //                                  dummy_cycle sets here
    //
    // 22          DUMMY1               dummy_cycle_rereg sets here
    //                                  capture word_write_disable[1] here from [0] by qualifying dummy_cycle && !dummy_cycle_rereg
    // 23          DUMMY2           -   spi_shift_reg needs to capture wb_dat_i here to present it on 24 if spi_rnw
    //                                  capture word_write_disable[0] here from [0] by dummy_cycle && dummy_cycle_rereg
    //                                  dummy_cycle clears here b/c dummy_cycle_rereg is set
    // 24          DATA[31]
    // 25          DATA{30]
    // 26          DATA[29]
    // 27          DATA[28]
    // 28          DATA[27]
    // 29          DATA[26]
    // 30          DATA[25]
    // 31          DATA[24]
    // 32          DATA[23]
    // 33          DATA[22]
    // 34          DATA[21]
    // 35          DATA[20]
    // 36          DATA[19]
    // 37          DATA[18]
    // 38          DATA[17]
    // 39          DATA[16]
    // 40          DATA[15]
    // 41          DATA[14]
    // 42          DATA[13]
    // 43          DATA[12]
    // 44          DATA[11]
    // 45          DATA[10]
    // 46          DATA[09]
    // 47          DATA[08]
    // 48          DATA[07]
    // 49          DATA[06]
    // 50          DATA[05]
    // 51          DATA[04]
    // 52          DATA[03]
    // 53          DATA[02]
    // 54          DATA[01]
    // 55          DATA[00]     - spi_shift_register is complete the (wb_clk) clock cycle AFTER this
    always @(posedge wb_clk_i) begin
        if (spi_cs_sync[1]) spi_counter <= {7{1'b0}};
        else if (!spi_counter[6] && spi_cclk_rflag) spi_counter <= spi_counter + 1;
        
        spi_cclk_sync <= {spi_cclk_sync[0], spi_cclk_i};
        spi_cs_sync <= {spi_cs_sync[0], spi_cs_i};
        spi_mosi_sync <= {spi_mosi_sync[0], spi_mosi_i};

        if (wb_ack_i) wb_cycle <= 1'b0;
        else if (spi_cclk_rflag) begin
            if ((address_cycle_stage && spi_shift_reg[0]) || (data_cycle_stage && !spi_rnw_hold))
                wb_cycle <= 1'b1;
        end
        
        if (spi_cclk_rflag && address_cycle_stage) spi_rnw_hold <= spi_shift_reg[0];
        if (spi_cclk_rflag && address_cycle_stage) spi_addr_hold <= spi_shift_reg[1 +: 20];
                
        if (spi_cclk_rflag) begin
            if (address_cycle_stage) dummy_clocks <= 1;
            else if (dummy_clocks_rereg) dummy_clocks <= 0;
            
            dummy_clocks_rereg <= dummy_clocks;
        end

        if (spi_cclk_rflag) begin
            if (dummy_clocks && !dummy_clocks_rereg) word_write_disable[1] <= spi_shift_reg[0];
            if (dummy_clocks && dummy_clocks_rereg) word_write_disable[0] <= spi_shift_reg[0];
        end                    
        // we have to hold off here through the dummy bits! that's what allows us
        // to hold off and use the shift register as storage.
        // dummy_clocks gets set at address_cycle_stage. this is fine,
        // because wb_cycle is *generated* by address_cycle_stage on reads.
        // then when address_cycle_stage + 1 comes around, 
        if (wb_cycle && wb_ack_i && spi_rnw_hold) 
            spi_shift_reg <= wb_dat_i;
        else if (spi_cclk_shift) begin
            spi_shift_reg <= {spi_shift_reg[30:0], spi_mosi_sync[1]};
        end
    end
    
    generate
        if (DEBUG == "TRUE") begin : ILA
            wb_spi_ila u_ila(.clk(wb_clk_i),
                             .probe0(spi_cclk_sync[1]),
                             .probe1(spi_mosi_sync[1]),
                             .probe2(spi_cs_sync[1]),
                             .probe3(spi_shift_reg));
        end
    endgenerate    
    assign wb_adr_o = { spi_addr_hold, 2'b00 };
    assign wb_we_o = !spi_rnw_hold;
    assign wb_sel_o = { {2{!word_write_disable[1]}}, {2{!word_write_disable[0]}} };
    assign wb_cyc_o = wb_cycle;
    assign wb_stb_o = wb_cycle;
    assign wb_dat_o = spi_shift_reg;

    assign spi_miso_o = spi_shift_reg[31];

endmodule
