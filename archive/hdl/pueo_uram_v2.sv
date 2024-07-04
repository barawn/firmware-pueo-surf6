`timescale 1ns / 1ps
// the ZU25 has 48 URAM blocks per. Each channel needs 96 bits: URAMs are quantized in units of 72.
// We handle this by jumping to a 500 MHz domain.
// Each URAM handles 24k samples, since each one is groups of 6. This is 8 us. So we use 4 each at first,
// requiring an address length of 14 bits, or 16384*6 = 98,304 samples = 32.768 us. We can double
// that for the ZU47DR.
//
// Note that we measure things here in "ticks" of 2/3 of a ns. In those units,
// memclk is 3 ticks, aclk is 4 ticks.
//
// Unlike the v1 module, the readout here is _fast_, because I forgot that
// the readout *latency* matters, because it prevents the *next*
// buffer from reading out.
//
// This module also provides a "flag" 
module pueo_uram_v2 #(parameter NSAMP=8,
                   parameter NBIT=12,
                   parameter RDLEN=1024,
                   parameter ADDRLEN=14,
                   parameter ADDRBITS=16)(
        input aclk,
        input aclk_sync_i,
        input aclk_rst_i,
        input [NSAMP*NBIT-1:0] dat_i,

        input memclk,
        input memclk_sync_i,

        input [ADDRBITS-1:0] s_axis_tdata,
        input                s_axis_tvalid,
        output               s_axis_tready,
        
        // this *isn't* actually an AXI4-Stream.
        // I should rename these. They need to write into
        // a FIFO that can give at least 4 write's notice on tready.
        output [NBIT*6-1:0] m_axis_tdata,
        output              m_axis_tvalid,
        input               m_axis_tready
    );
    
    // this helps us with the output delay
    localparam NUM_URAM = 1<<(ADDRLEN-12);
    localparam MEM_SIZE = 72*(1<<ADDRLEN);
    localparam MIN_LATENCY = 2;

    // This is the actual output delay from the URAM
    // I have no idea why this is so big, but HEY,
    // simulation! 
    localparam OUTDELAY = 10;

    localparam RDCNTLEN = $clog2(RDLEN);    
    
    reg           aclk_reset_seen = 0;
    reg               aclk_reset = 0;
    // this has a path constraint of 6 ticks: it goes valid at tick 6 and needs to get to its destination by tick 12.
    reg               write_reset = 0;
    reg               write_run = 0;
    reg               write_write = 0;

    // Goddamnit, just use a freaking DSP for this.
    (* USE_DSP48 = "YES" *)
    reg [ADDRLEN-1:0] write_addr = {ADDRLEN{1'b0}};
    reg               write_addr_reset = 0;
    // these have *psycho* fanout, so force them small
//    (* max_fanout = 8 *)
    reg [1:0]         write_phase = {2{1'b0}};
    reg [2:0]         buffer_phase = {3{1'b0}};
    reg [NBIT*NSAMP*3-1:0] buffer_data = {NBIT*NSAMP*3{1'b0}};
    reg [NBIT*6-1:0]  write_data = {NBIT*6{1'b0}};

    reg [ADDRLEN-1:0] base_addr = {ADDRLEN{1'b0}};
    reg [ADDRLEN-1:0] base_addr_rereg = {ADDRLEN{1'b0}};
    
    reg               reading = 0;
    reg               reading_rereg = 0;
    reg [1:0] read_en = 0;
    reg [RDCNTLEN:0] readcount = {RDCNTLEN+1{1'b0}};
    reg [RDCNTLEN:0] readcount_rereg = {RDCNTLEN+1{1'b0}};
    
    
    (* USE_DSP48 = "YES" *)
    reg [ADDRLEN-1:0] full_addr = {ADDRLEN{1'b0}};
    reg [ADDRLEN-1:0] full_addr_reg = {ADDRLEN{1'b0}};
    
    (* KEEP = "TRUE" *)
    reg [2:0] memclk_sync_local = 2'b00;    
        
    always @(posedge aclk) begin
        // just relock to the input. aclk_sync_i indicates the first phase, so when it comes in, capture the second
        buffer_phase <= {buffer_phase[1], aclk_sync_i, buffer_phase[2]};
        if (buffer_phase[0]) buffer_data[0 +: NBIT*NSAMP] <= dat_i;
        if (buffer_phase[1]) buffer_data[NBIT*NSAMP +: NBIT*NSAMP] <= dat_i;
        if (buffer_phase[2]) buffer_data[2*NBIT*NSAMP +: NBIT*NSAMP] <= dat_i;

        if (aclk_rst_i) aclk_reset_seen <= 1;
        else if (buffer_phase[2]) aclk_reset_seen <= 0;
        
        // this is a full cycle long, begins at tick 0 and sampled at write_phase[1]. So it gets a path constraint of 6 ticks.
        if (buffer_phase[2]) aclk_reset <= aclk_reset_seen;
    end
    always @(posedge memclk) begin
        // decouple from memclk_sync
        memclk_sync_local <= { memclk_sync_local[1:0], memclk_sync_i };
        // Since we're now 3 delayed, write_phase resets 
        if (memclk_sync_i) write_phase <= {2{1'b0}};
        else write_phase <= write_phase + 1;

        write_addr_reset <= (write_phase == 2) && write_reset;
        
        if (write_phase == 1) write_reset <= aclk_reset;
        // start after first reset
        if (write_phase == 3) if (write_reset) write_run <= 1; 

        write_write <= write_run;

        // god you're a pain in the neck
        if (write_addr_reset) write_addr <= {ADDRLEN{1'b0}};
        else write_addr <= write_addr + 1;

        // if write phase 3, we capture the data captured at tick 4 in aclk. write_phase[3] is seen at tick 12,
        // so this is an 8 tick delay.
        if (write_run) begin
            case (write_phase)
                3: write_data <= buffer_data[0 +: 6*NBIT];
                0: write_data <= buffer_data[6*NBIT +: 6*NBIT];
                1: write_data <= buffer_data[12*NBIT +: 6*NBIT];
                2: write_data <= buffer_data[18*NBIT +: 6*NBIT];
            endcase
        end
        
        if (s_axis_tvalid && !reading) base_addr <= s_axis_tdata;

        if (s_axis_tvalid && !reading) reading <= 1;
        else if (write_phase == 1 && readcount[RDCNTLEN]) reading <= 0;
        
        reading_rereg <= reading;
        
        if (write_phase == 0 && reading && m_axis_tready) begin
            readcount <= readcount + 1;
        end
    
        base_addr_rereg <= base_addr;
        readcount_rereg <= readcount;
        
        full_addr <= base_addr_rereg + readcount_rereg;
        full_addr_reg <= full_addr;
        
        read_en <= { read_en[0], (write_phase == 0 && reading) };
    end
    
    
    // The MEM_SIZE here is 72*2^14 = 1,179,648 bits = 4 UltraRAM blocks per channel (32 total)
    // NUM_URAM is 4, so READ_LATENCY_B should be 6 but it never actually seems correct.
    xpm_memory_sdpram #(.MEMORY_PRIMITIVE("ultra"), .MEMORY_SIZE(MEM_SIZE),
                        .MESSAGE_CONTROL(0),
                        .WRITE_MODE_B("read_first"),
                        .READ_DATA_WIDTH_B(72),
                        .READ_LATENCY_B(MIN_LATENCY+NUM_URAM),
                        .AUTO_SLEEP_TIME(0),
                        .BYTE_WRITE_WIDTH_A(72),
                        .WRITE_DATA_WIDTH_A(72),
                        .USE_MEM_INIT(0),
                        .ADDR_WIDTH_A(ADDRLEN),
                        .ADDR_WIDTH_B(ADDRLEN))
                            u_buffer( .addra( write_addr ),
                                      .addrb( full_addr_reg ),
                                      .clka( memclk ),
                                      .dina( write_data ),
                                      .doutb( m_axis_tdata ),
                                      .ena( write_write ),
                                      .wea( 1'b1 ),
                                      .enb( read_en[1] ),
                                      .regceb( 1'b1 ),
                                      .rstb( 1'b0 ) );            

    assign s_axis_tready = reading && !reading_rereg;

    // takes 10 clocks from enable for it to pop out the URAM. Yes, this is not
    // 6 (MIN_LATENCY + NUM_URAM), don't ask me why, I have no idea.
    wire read_valid_delay;
    // -2 b/c of the SRL (0=1 clock delay) and following FD.
    SRLC32E u_valid_delay(.CE(1'b1),.D(read_en[1]),.CLK(memclk),.Q(read_valid_delay),.A(OUTDELAY-2));
    FD u_valid_out(.D(read_valid_delay),.C(memclk),.Q(m_axis_tvalid));
            
endmodule
