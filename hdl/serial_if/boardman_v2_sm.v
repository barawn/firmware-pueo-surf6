`timescale 1ns / 1ps
`include "interfaces.vh"
`define DLYFF #0.5
// Core logic for the boardman interface
// This takes an AXI4-stream input for commanding
// and generates an AXI4-stream output for responses
module boardman_v2_sm( 
        input clk,
        input rst,
        output [19:0] adr_o,
        output [31:0] dat_o,
        input  [31:0] dat_i,
        output        en_o,
        output        wr_o,
        output [3:0]  wstrb_o,
        input         ack_i,

        input [1:0]   burst_size_i,
        input [7:0]   address_i,

        // input AXI4-stream for commands
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( axis_rx_ , 8 ),
        input         axis_rx_tlast,
        input         axis_rx_tuser,
        // output for data
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( axis_tx_ , 8 ),
        output        axis_tx_tlast );

    parameter DEBUG = "FALSE";
    parameter SIMULATION = "FALSE";
    parameter USE_ADDRESS = "FALSE";

    reg en = 0;
    reg wr = 0;
    reg [3:0] wstrb = {4{1'b0}};
    reg [31:0] data = {32{1'b0}};
    // this is the 'don't increment address' bit (bit 22) which has
    // to be set in the board manager, because normally all addresses
    // with bit 22 are handled by the board manager.
    reg addr_increment = 0;

    // output registers
    reg [7:0] axis_tx_tdata_reg = {8{1'b0}};
    reg       axis_tx_tlast_reg = 1'b0;
    
    
    reg [7:0] len = {8{1'b0}};
    reg write_last = 0;

    reg [23:0] address = {24{1'b0}};
    reg [23:0] capture_address = {24{1'b0}};
    // On burst reads we auto-align addresses. 
    wire [1:0] lowbit_mask = { !burst_size_i[1], !burst_size_i[1] && !burst_size_i[0] };
    wire [7:0] lowbyte_mask = { 6'h3F, lowbit_mask };
    wire [7:0] aligned_address = (capture_address[23] && capture_address[22]) ? axis_rx_tdata & lowbyte_mask : axis_rx_tdata;
        
    localparam FSM_BITS=5;
    localparam [FSM_BITS-1:0] IDLE=0;
    // extra states if we use addressed mode
    localparam [FSM_BITS-1:0] ADDRESS_CHECK = 24;
    localparam [FSM_BITS-1:0] ADDRESS_DUMP = 25;
    // address comes in big-endian, just freaking because
    localparam [FSM_BITS-1:0] ADDR2=1;
    localparam [FSM_BITS-1:0] ADDR1=2;
    localparam [FSM_BITS-1:0] ADDR0=3;
    localparam [FSM_BITS-1:0] READLEN=4;
    localparam [FSM_BITS-1:0] READADDR2=5;
    localparam [FSM_BITS-1:0] READADDR1=6;
    localparam [FSM_BITS-1:0] READADDR0=7;
    localparam [FSM_BITS-1:0] READCAPTURE=8;
    localparam [FSM_BITS-1:0] READDATA0=9;
    localparam [FSM_BITS-1:0] READDATA1=10;
    localparam [FSM_BITS-1:0] READDATA2=11;
    localparam [FSM_BITS-1:0] READDATA3=12;    
    // data comes in little-endian, as if it's byte-addressed
    localparam [FSM_BITS-1:0] WRITE0=13;
    localparam [FSM_BITS-1:0] WRITE1=14;
    localparam [FSM_BITS-1:0] WRITE2=15;
    localparam [FSM_BITS-1:0] WRITE3=16;
    localparam [FSM_BITS-1:0] WRITEEN=17;
    localparam [FSM_BITS-1:0] WRITEADDR2=18;
    localparam [FSM_BITS-1:0] WRITEADDR1=19;
    localparam [FSM_BITS-1:0] WRITEADDR0=20;
    localparam [FSM_BITS-1:0] WRITELEN=21;
    localparam [FSM_BITS-1:0] RESET0 = 22;
    localparam [FSM_BITS-1:0] RESET1 = 23;
    // yikes this is big
    reg [FSM_BITS-1:0] state = RESET0;

    wire [FSM_BITS-1:0] FIRST_STATE = (USE_ADDRESS == "TRUE") ? ADDRESS_CHECK : ADDR2;

    always @(posedge clk) begin
        case (state)
            IDLE: if (axis_rx_tvalid && !axis_rx_tlast && !axis_rx_tuser) state <= `DLYFF FIRST_STATE;
            ADDRESS_CHECK: if (axis_rx_tvalid) begin
                if (axis_rx_tlast || axis_rx_tuser) state <= `DLYFF IDLE;
                else begin
                    if (axis_rx_tdata == address_i) state <= `DLYFF ADDR2;
                    else state <= `DLYFF ADDRESS_DUMP;
                end
            end
            ADDRESS_DUMP: if (axis_rx_tvalid && (axis_rx_tlast || axis_rx_tuser)) state <= `DLYFF IDLE;
            ADDR2: if (axis_rx_tvalid) begin
                if (axis_rx_tlast || axis_rx_tuser) state <= `DLYFF IDLE;
                else state <= `DLYFF ADDR1;
            end
            ADDR1: if (axis_rx_tvalid) begin
                if (axis_rx_tlast || axis_rx_tuser) state <= `DLYFF IDLE;
                else state <= `DLYFF ADDR0;
            end
            ADDR0: if (axis_rx_tvalid) begin
                if (axis_rx_tlast || axis_rx_tuser) state <= `DLYFF IDLE;
                else begin
                    if (capture_address[23]) begin
                        // Figure out where we start.
                        // Note that capture_address[1:0] isn't valid yet, grab it from the RX
                        if (axis_rx_tdata[1:0] == 2'b00) state <= `DLYFF WRITE0;
                        else if (axis_rx_tdata[1:0] == 2'b01) state <= `DLYFF WRITE1;
                        else if (axis_rx_tdata[1:0] == 2'b10) state <= `DLYFF WRITE2;
                        else if (axis_rx_tdata[1:0] == 2'b11) state <= `DLYFF WRITE3;
                    end else state <= `DLYFF READLEN;
                end
            end
            READLEN: if (axis_rx_tvalid) begin
                // TLAST *should* be asserted here.
                if (axis_rx_tuser || !axis_rx_tlast) state <= `DLYFF IDLE;
                else state <= `DLYFF READADDR2;
            end
            // This writes the address back, byte by byte
            READADDR2: if (axis_tx_tready) state <= `DLYFF READADDR1;
            READADDR1: if (axis_tx_tready) state <= `DLYFF READADDR0;
            READADDR0: if (axis_tx_tready) state <= `DLYFF READCAPTURE;
            READCAPTURE: if (ack_i) begin
                // Figure out where we start. Note that 'address' here is
                // already burst-aligned, so if we're bursting, it'll only go to the appropriate
                // address.
                if (address[1:0] == 2'b00) state <= `DLYFF READDATA0;
                else if (address[1:0] == 2'b01) state <= `DLYFF READDATA1;
                else if (address[1:0] == 2'b10) state <= `DLYFF READDATA2;
                else if (address[1:0] == 2'b11) state <= `DLYFF READDATA3;
            end
            // If bursting in byte mode, jump to READCAPTURE to grab data again. Otherwise
            // go to READDATA1.
            READDATA0: if (axis_tx_tready) begin
                if (!len) state <= `DLYFF IDLE;
                else if (addr_increment || (burst_size_i != 2'b00)) state <= `DLYFF READDATA1;
                else state <= `DLYFF READCAPTURE;
            end
            // If bursting in byte mode OR in word mode (NOT in dword mode) jump to
            // READCAPTURE to grab data again. Otherwise go to READDATA2.
            READDATA1: if (axis_tx_tready) begin
                if (!len) state <= `DLYFF IDLE;
                else if (addr_increment || (burst_size_i == 2'b10)) state <= `DLYFF READDATA2;
                else state <= `DLYFF READCAPTURE;
            end
            // If bursting in byte mode, jump to READCAPTURE to grab data again. Otherwise
            // go to READDATA3.
            READDATA2: if (axis_tx_tready) begin
                if (!len) state <= `DLYFF IDLE;
                else if (addr_increment || (burst_size_i != 2'b00)) state <= `DLYFF READDATA3;
                else state <= `DLYFF READCAPTURE;
            end
            // No matter what, go to READCAPTURE to grab next data.
            READDATA3: if (axis_tx_tready) begin
                if (!len) state <= `DLYFF IDLE;
                else state <= `DLYFF READCAPTURE;
            end
            // soooo... this will do wackadoodle things if an
            // error comes in the middle. Maybe buffer the writes.
            // Check that later.
            //
            // The burst_size_i qualification makes it so we interpret these differently.
            // If 00, we go WRITEx->WRITEEN->WRITEx->WRITEEN repeatedly.
            // If 01, we go WRITE0/2->WRITE1/3->WRITEEN repeatedly.
            // If 10, we go WRITE0->WRITE1->WRITE2->WRITE3->WRITEEN repeatedly.
            // Note that if you screw up and do it unaligned, it'll go like
            // WRITE3->WRITEEN->WRITE0->WRITE1->WRITE2->WRITE3->WRITEEN
            // which, I guess could be useful
            WRITE0: if (axis_rx_tvalid) begin
                if (axis_rx_tuser) state <= `DLYFF IDLE;
                else if (axis_rx_tlast || (!addr_increment && (burst_size_i == 2'b00) )) state <= `DLYFF WRITEEN;
                else state <= `DLYFF WRITE1;
            end
            WRITE1: if (axis_rx_tvalid) begin
                if (axis_rx_tuser) state <= `DLYFF IDLE;
                else if (axis_rx_tlast || (!addr_increment && (burst_size_i == 2'b01 || burst_size_i == 2'b00) )) state <= `DLYFF WRITEEN;
                else state <= `DLYFF WRITE2;
            end
            WRITE2: if (axis_rx_tvalid) begin
                if (axis_rx_tuser) state <= `DLYFF IDLE;
                else if (axis_rx_tlast || (!addr_increment && (burst_size_i == 2'b00) )) state <= `DLYFF WRITEEN;
                else state <= `DLYFF WRITE3;
            end
            WRITE3: if (axis_rx_tvalid) begin
                if (axis_rx_tuser) state <= `DLYFF IDLE;
                else state <= `DLYFF WRITEEN;
            end
            WRITEEN: if (ack_i) begin
                if (write_last) state <= `DLYFF WRITEADDR2;
                else if (!addr_increment) begin
                    if (burst_size_i == 2'b00) begin
                        // figure out where we jump back to
                        if (address[1:0] == 2'b00) state <= `DLYFF WRITE0;
                        else if (address[1:0] == 2'b01) state <= `DLYFF WRITE1;
                        else if (address[1:0] == 2'b10) state <= `DLYFF WRITE2;
                        else if (address[1:0] == 2'b11) state <= `DLYFF WRITE3;                
                    end else if (burst_size_i == 2'b01) begin
                        if (address[1]) state <= `DLYFF WRITE2;
                        else state <= `DLYFF WRITE3;
                    end else state <= `DLYFF WRITE0;
                end else state <= `DLYFF WRITE0;
            end
            WRITEADDR2: if (axis_tx_tready) state <= `DLYFF WRITEADDR1;
            WRITEADDR1: if (axis_tx_tready) state <= `DLYFF WRITEADDR0;
            WRITEADDR0: if (axis_tx_tready) state <= `DLYFF WRITELEN;
            WRITELEN: if (axis_tx_tready) state <= `DLYFF IDLE;
            RESET0: state <= `DLYFF RESET1;
            RESET1: state <= `DLYFF IDLE;
        endcase
                
        // deal with the address increments
        if (((state == WRITEEN && ack_i) || (state == READDATA3 && axis_tx_tready)) && addr_increment)
            address <= { 2'b00, address[21:2], 2'b00 } + 4;
        else if (state == ADDR0)
            address <= {capture_address[23:8],aligned_address};
        
        if (state == ADDR2) addr_increment <= !axis_rx_tdata[6];
        
        if (state == ADDR2) capture_address[23:16] <= axis_rx_tdata;
        if (state == ADDR1) capture_address[15:8] <= axis_rx_tdata;
        if (state == ADDR0) capture_address[7:0] <= axis_rx_tdata;
    
        if (state == WRITE0 && axis_rx_tvalid) data[7:0] <= axis_rx_tdata;
        else if (state == READCAPTURE && ack_i) data[7:0] <= dat_i[7:0];
        
        if (state == WRITE1 && axis_rx_tvalid) data[15:8] <= axis_rx_tdata;
        else if (state == READCAPTURE && ack_i) data[15:8] <= dat_i[15:8];
        
        if (state == WRITE2 && axis_rx_tvalid) data[23:16] <= axis_rx_tdata;
        else if (state == READCAPTURE && ack_i) data[23:16] <= dat_i[23:16];
        
        if (state == WRITE3 && axis_rx_tvalid) data[31:24] <= axis_rx_tdata;
        else if (state == READCAPTURE && ack_i) data[31:24] <= dat_i[31:24];
        
        if (state == IDLE || (state == WRITEEN && ack_i)) wstrb <= {4{1'b0}};
        else begin
            if (state == WRITE0) wstrb[0] <= 1;
            if (state == WRITE1) wstrb[1] <= 1;
            if (state == WRITE2) wstrb[2] <= 1;
            if (state == WRITE3) wstrb[3] <= 1;
        end
        
        if (state == IDLE) write_last <= 0;
        else if (state == WRITE0 || state == WRITE1 || 
                 state == WRITE2 || state == WRITE3) begin
            if (axis_rx_tvalid && axis_rx_tlast && !axis_rx_tuser) 
                write_last <= 1;
            else 
                write_last <= 0;
        end
        
        // length handling
        if (state == IDLE) len <= {8{1'b0}};
        else if ((state == WRITE0 || state == WRITE1 || state == WRITE2 || state == WRITE3) && axis_rx_tvalid) len <= len + 1;
        else if ((state == READDATA0 || state == READDATA1 || state == READDATA2 || state == READDATA3) && axis_tx_tready) len <= len - 1;
        else if ((state == READLEN) && axis_rx_tvalid) len <= axis_rx_tdata;
        
        // outgoing data determination. Here we need to prep things the cycle before.
        if (state == READLEN || state == WRITEEN) 
            axis_tx_tdata_reg <= capture_address[23:16];
        else if ((state == READADDR2 || state == WRITEADDR2) && axis_tx_tready)
            axis_tx_tdata_reg <= capture_address[15:8];
        else if ((state == READADDR1 || state == WRITEADDR1) && axis_tx_tready)
            axis_tx_tdata_reg <= capture_address[7:0];
        else if (state == READCAPTURE && ack_i) begin
            if (address[1:0] == 2'b00) axis_tx_tdata_reg <= dat_i[7:0];
            else if (address[1:0] == 2'b01) axis_tx_tdata_reg <= dat_i[15:8];
            else if (address[1:0] == 2'b10) axis_tx_tdata_reg <= dat_i[23:16];
            else if (address[1:0] == 2'b11) axis_tx_tdata_reg <= dat_i[31:24];
        end 
        // No! These don't come from dat_i, they come from *data*.
        // dat_i is allowed to change after READCAPTURE. If we're doing a burst read,
        // this data capture won't matter because axis_tx_tvalid is not 1 in READCAPTURE
        // and we jump back to READCAPTURE (where it's regrabbed from dat_i).
        else if (state == READDATA0 && axis_tx_tready) axis_tx_tdata_reg <= data[15:8];
        else if (state == READDATA1 && axis_tx_tready) axis_tx_tdata_reg <= data[23:16];
        else if (state == READDATA2 && axis_tx_tready) axis_tx_tdata_reg <= data[31:24];
        else if (state == WRITEADDR0 && axis_tx_tready) axis_tx_tdata_reg <= len;

        // tlast generation
        if (state == WRITEADDR0 && axis_tx_tready) axis_tx_tlast_reg <= 1;
        // TLAST goes when we're going to TRANSIT to 0 in the next guy.
        // There's one special case we need to handle, which is in READCAPTURE if len is already 0.
        // This happens if READDATA0 is going to be the final byte. Note that READDATA3 is excluded
        // here because the next state after READDATA3 is always READCAPTURE, so the len = 0 catches
        // that there.
        else if ((state == READCAPTURE && ack_i && (len == 0)) || 
                 (((state == READDATA0 || state == READDATA1 || state == READDATA2) && axis_tx_tready) && 
                 (len == 1))) axis_tx_tlast_reg <= 1;
        else axis_tx_tlast_reg <= 0;
    end

    // tready generation. Does NOT happen in IDLE unless we have gar-bage to zip through.    
    // The state names describe what's currently on the TDATA busses.
    wire idle_dump = (state == IDLE && axis_rx_tvalid && (axis_rx_tlast || axis_rx_tuser));

    ////// SIMULATION STUFF
    reg [21:0] simadr = {22{1'b0}};
    reg [31:0] simdat = {32{1'b0}};
    reg simen = 0;
    reg simwr = 0;
    reg [3:0] simwstrb = {4{1'b0}};

    // synthesis translate off

    task automatic BMWR(input [21:0] address, input [31:0] value);
        begin
            @(posedge clk); #1 simen = 1; simadr = address; simdat = value; simwstrb = 4'hF; simwr = 1; @(posedge clk);
            while (!ack_i) @(posedge clk);
            #1 simen = 0; simwr = 0;
        end
    endtask
    
    task automatic BMRD(input [21:0] address, output [31:0] value);
        begin
            @(posedge clk); #1 simen = 1; simadr = address; @(posedge clk);
            while (!ack_i) @(posedge clk);
            value = dat_i;
            #1 simen = 0;
        end
    endtask
        

    // synthesis translate on

    generate
        if (SIMULATION == "TRUE") begin : INTSIGS
            assign adr_o = simadr[21:2];
            assign dat_o = simdat;
            assign en_o = simen;
            assign wr_o = simwr;
            assign wstrb_o = simwstrb;
        end else begin : REAL
            assign adr_o = address[21:2];
            assign dat_o = data;
            assign en_o = (state == WRITEEN) || (state == READCAPTURE);
            assign wr_o = (state == WRITEEN);
            assign wstrb_o = wstrb;
        end                
    endgenerate

    ////// END SIMULATION STUFF    


    // RX path assigns
    assign axis_rx_tready = (state == ADDRESS_CHECK || state == ADDRESS_DUMP || state == ADDR2 || state == ADDR1 || 
                             state == ADDR0 || state == READLEN ||
                             state == WRITE0 || state == WRITE1 || state == WRITE2 ||
                             state == WRITE3 || idle_dump);
    // TX path assigns
    assign axis_tx_tdata = axis_tx_tdata_reg;
    assign axis_tx_tlast = axis_tx_tlast_reg;    
    // tvalid generation
    assign axis_tx_tvalid = (state == READDATA0 || state == READDATA1 || state == READDATA2 ||
                             state == READDATA3 || state == READADDR0 || state == READADDR1 ||
                             state == READADDR2 || state == WRITEADDR0 || state == WRITEADDR1 ||
                             state == WRITEADDR2 || state == WRITELEN);

    // register interface assigns
    
    
endmodule        