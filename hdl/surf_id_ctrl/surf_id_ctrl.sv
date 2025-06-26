`timescale 1ns / 1ps
`include "interfaces.vh"
// Clock monitors go here.
module surf_id_ctrl(
        input wb_clk_i,
        input wb_rst_i,
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 11, 32),
        
        input [15:0] sysref_phase_i,
        
        input [7:0] gpi_i,
        output [7:0] gpo_o,
        output [4:0] sync_offset_o,
        
        input rundo_sync_i,
        input runnoop_live_i,
        
        input [7:0] adc_sigdet_i,
        input [7:0] adc_cal_frozen_i,
        output [7:0] adc_cal_freeze_o,
            
        // data from TURFIO
        input hsk_rx_i,
        // data to TURFIO
        input hsk_tx_i,
        // watchdog trigger and null byte.
        // watchdog trigger blows up the housekeeping path entirely.
        output watchdog_trigger_o,
        output watchdog_null_o,
        
        output rfdc_rst_o,
                
        output aclk_ok_o,
        output rxclk_ok_o,
        output gtpclk_ok_o,
        output rackclk_ok_o,
                                
        input aclk_i,    // 375 MHz
        input ifclk_i,     // 125 MHz
        input gtp_clk_i,    // GTP clock
        input rackclk_i,    // receive clock from TURFIO before MMCM
        input rxclk_i,     // receive clock from TURFIO after MMCM
        input clk300_i      // 300 MHz used for IDELAYCTRL
    );
    
    parameter [31:0] DEVICE = "SURF";
    parameter [31:0] VERSION = {32{1'b0}};
    parameter WB_CLK_TYPE = "PSCLK";
    parameter NUM_GPO = 8;
    parameter NUM_GPI = 8;
    parameter [4:0] SYNC_OFFSET_DEFAULT = 7;
    parameter WB_ADR_BITS = 11;
    
    wire dna_data;
    reg dna_shift = 0;
    reg dna_read = 0;
    (* CUSTOM_CC_SRC = WB_CLK_TYPE *)
    reg [NUM_GPO-1:0] ctrlstat_gpo = {NUM_GPO{1'b0}};
    (* CUSTOM_CC_DST = WB_CLK_TYPE *)
    reg [NUM_GPI-1:0] ctrlstat_gpi = {NUM_GPI{1'b0}};
    
    // This is standardized now
    (* CUSTOM_CC_SRC = WB_CLK_TYPE *)
    reg [4:0] sync_offset = SYNC_OFFSET_DEFAULT;

    (* CUSTOM_CC_DST = WB_CLK_TYPE *)
    reg [15:0] sysref_phase = {16{1'b0}};

    // watchdog fun
    reg watchdog_trigger_enable = 0;
    reg watchdog_trigger = 0;
    reg watchdog_trigger_rereg = 0;
    reg watchdog_null = 0;
    reg rackclk_was_ok = 0;

    reg rundo_sync_seen = 0;
    reg runnoop_live_seen = 0;
    
    reg [7:0] cal_freeze = {8{1'b0}};
    
    (* CUSTOM_CC_SRC = WB_CLK_TYPE *)
    reg rfdc_stream_reset = 1;
    
    // top 8 bits are a global stat: top bit is TURFIO ready
    wire [31:0] ctrlstat_reg = { rackclk_ok_o, {5{1'b0}}, rfdc_stream_reset, watchdog_trigger_enable,
                                 rundo_sync_seen, runnoop_live_seen, {1{1'b0}}, sync_offset, // 23:16
                                 ctrlstat_gpi,      // 15:8
                                 ctrlstat_gpo };    // 7:0
    
    // housekeeping timer, doubly used for sending/receiving nulls
    localparam [11:0] PACKET_TIMER_RESET_VAL = 12'd696;
    localparam [11:0] WATCHDOG_RESET_VAL = 12'd496;
    reg [11:0] packet_timer_count = PACKET_TIMER_RESET_VAL;
    reg [3:0] hsk_packet_count = {4{1'b0}};
        
    wire sel_internal = (wb_adr_i[6 +: (WB_ADR_BITS-6)] == 0);
    wire [31:0] wishbone_registers[15:0];

//        input [7:0] adc_sigdet_i,
//        input [7:0] adc_cal_frozen_i,
//        output [7:0] adc_cal_freeze_o,

    wire [31:0] adc_cal_ports = { {8{1'b0}}, adc_sigdet_i, adc_cal_frozen_i, cal_freeze };
    
        // Convenience stuff. These allow setting up wishbone registers easier.
		// BASE needs to be defined to convert the base address into an index.
		localparam BASEWIDTH = 4;
		function [BASEWIDTH-1:0] BASE;
				input [11:0] bar_value;
				begin
						BASE = bar_value[5:2];
				end
		endfunction
		`define OUTPUT(addr, x, range, dummy)																				\
					assign wishbone_registers[ addr ] range = x
		`define SELECT(addr, x, dummy, dummy1)																			\
					wire x;																											\
					localparam [BASEWIDTH-1:0] addr_``x = addr;															\
					assign x = (sel_internal && wb_cyc_i && wb_stb_i && wb_we_i && wb_ack_o && (BASE(wb_adr_i) == addr_``x))
		`define OUTPUTSELECT(addr, x, y, dummy)																		\
					wire y;																											\
					localparam [BASEWIDTH-1:0] addr_``y = addr;															\
					assign y = (sel_internal && wb_cyc_i && wb_stb_i && wb_ack_o && (BASE(wb_adr_i) == addr_``y));	\
					assign wishbone_registers[ addr ] = x

		`define SIGNALRESET(addr, x, range, resetval)																	\
					always @(posedge wb_clk_i) begin																			\
						if (wb_rst_i) x <= resetval;																				\
						else if (sel_internal && wb_cyc_i && wb_stb_i && wb_we_i && (BASE(wb_adr_i) == addr))		\
							x <= wb_dat_i range;																						\
					end																												\
					assign wishbone_registers[ addr ] range = x
		`define WISHBONE_ADDRESS( addr, name, TYPE, par1, par2 )														\
					`TYPE(BASE(addr), name, par1, par2)

    // reg 0
    `WISHBONE_ADDRESS( 12'h000, DEVICE, OUTPUT, [31:0], 0);
    // reg 1
    `WISHBONE_ADDRESS( 12'h004, VERSION, OUTPUT, [31:0], 0);
    // reg 2
    `WISHBONE_ADDRESS( 12'h008, { {31{1'b0}}, dna_data }, OUTPUTSELECT, sel_dna, 0);
    // reg 3
    `WISHBONE_ADDRESS( 12'h00C, ctrlstat_reg, OUTPUTSELECT, sel_ctrlstat, 0);
    // reg 4
    `WISHBONE_ADDRESS( 12'h010, hsk_packet_count, OUTPUT, [31:0], 0);
    // reg 5
    `WISHBONE_ADDRESS( 12'h014, sysref_phase, OUTPUT, [31:0], 0);
    // reg 6
    `WISHBONE_ADDRESS( 12'h018, adc_cal_ports, OUTPUTSELECT, sel_adc_cal_ports, 0);
    assign wishbone_registers[7] = wishbone_registers[3];
    assign wishbone_registers[8] = wishbone_registers[0];
    assign wishbone_registers[9] = wishbone_registers[1];
    assign wishbone_registers[10] = wishbone_registers[2];
    assign wishbone_registers[11] = wishbone_registers[3];
    assign wishbone_registers[12] = wishbone_registers[0];
    assign wishbone_registers[13] = wishbone_registers[1];
    assign wishbone_registers[14] = wishbone_registers[2];
    assign wishbone_registers[15] = wishbone_registers[3];
    
    wire [31:0] dat_internal = wishbone_registers[wb_adr_i[5:2]];
    reg         ack_internal = 0;
    
    wire ack_clockmon;
    wire [31:0] dat_clockmon;

    // if this is 9, for instance:
    // num_byte_gpo(0, 9) => 8 b/c (8*0+8) > 9 is false
    // num_byte_gpo(1, 9) => 1 b/c (8*1+8) > 9 and (9-8*1 = 1)
    // if this is 8 for instance
    // num_byte_gpo(0, 8) => 8 b/c (8*0+8) > 8 is false
    function num_byte_gpo;
        input integer idx;
        input integer max_num;
        begin
            // Check to see if we go past the ends
            if (8*idx + 8 > max_num) begin
                num_byte_gpo = max_num - 8*idx;
            end else begin
                // otherwise 8
                num_byte_gpo = 8;
            end
        end
    endfunction        
    
    // sigh, this has to be done in a generate block I think
    generate
        genvar gi;
        for (gi=0;gi<(NUM_GPO/8);gi=gi+1) begin : GPO_BYTE
            localparam THIS_BYTE_BITS = (8*gi + 8 > NUM_GPO) ? (NUM_GPO-8*gi) : 8;
            always @(posedge wb_clk_i) begin : GPO_BYTE_LOGIC
                if (wb_we_i && wb_sel_i[gi] && sel_ctrlstat) begin
                    ctrlstat_gpo[8*gi +: THIS_BYTE_BITS] <= wb_dat_i[8*gi +: THIS_BYTE_BITS];
                end
            end
        end
    endgenerate

    // we abuse the packet timer for two roles - it should be trivial to merge the logic.
    // running at 500 kbps, each bit is 2 us, and a null byte is 9 bit times long, or
    // 18 us, because a zero is
    // 0000000001
    // |        ^ stop bit
    // ^ start bit
    // so to watch for an incoming null, we look for 8.5 = 17 us = 3400 clocks
    // and to send an outgoing null we run for 9 = 18 us = 3600 clocks
    // we use a counter which is held in reset normally at 4096-3400, and then counts up
    // otherwise
    // it gets reset to 4096-3600 on a watchdog start and counts up
    always @(posedge wb_clk_i) begin
        sysref_phase <= sysref_phase_i;
    
        if (sel_adc_cal_ports && wb_we_i && wb_ack_o && wb_sel_i[0]) begin
            cal_freeze <= wb_dat_i[7:0];
        end    
        if (sel_ctrlstat && wb_we_i && wb_ack_o && wb_sel_i[2] && wb_dat_i[23]) rundo_sync_seen <= 1'b0;
        else if (rundo_sync_i) rundo_sync_seen <= 1'b1;
    
        if (sel_ctrlstat && wb_we_i && wb_ack_o && wb_sel_i[2] && wb_dat_i[22]) runnoop_live_seen <= 1'b0;
        else if (runnoop_live_i) runnoop_live_seen <= 1'b1;
    
        rackclk_was_ok <= rackclk_ok_o;
        if (watchdog_trigger_enable && (rackclk_was_ok && !rackclk_ok_o))
            watchdog_trigger <= 1;
        watchdog_trigger_rereg <= watchdog_trigger;

        // the packet counter keeps running after the watchdog is triggered, that's fine.        
        if (watchdog_trigger && !watchdog_trigger_rereg) packet_timer_count <= WATCHDOG_RESET_VAL;
        else if (hsk_tx_i && !watchdog_trigger) packet_timer_count <= PACKET_TIMER_RESET_VAL;
        else packet_timer_count <= packet_timer_count[10:0] + 1;

        if (packet_timer_count[11]) watchdog_null <= 0;
        else if (watchdog_trigger && !watchdog_trigger_rereg) watchdog_null <= 1;

        if (!hsk_rx_i) hsk_packet_count <= {4{1'b0}};
        else if (packet_timer_count[11]) hsk_packet_count <= hsk_packet_count + 1;
    
        ctrlstat_gpi <= gpi_i;
    
        ack_internal <= (wb_cyc_i && wb_stb_i && sel_internal) && !ack_internal;
        if (sel_dna && ~wb_we_i && wb_ack_o) dna_shift <= 1;
        else dna_shift <= 0;
        if (sel_dna && wb_we_i && wb_ack_o && wb_sel_i[3]) dna_read <= wb_dat_i[31];
        else dna_read <= 0;        

        if (sel_ctrlstat && wb_we_i && wb_ack_o) begin
            // the gpo stuff gets handled above due to stupidity
            if (wb_sel_i[2]) sync_offset <= wb_dat_i[16 +: 5];
            if (wb_sel_i[3]) begin
                watchdog_trigger_enable <= wb_dat_i[24];
                rfdc_stream_reset <= wb_dat_i[25];
            end                
        end
    end    
    
    // The custom attributes here allow us to extract information about the design at the
    // implemented design level.
    (* CUSTOM_DNA_VER = VERSION *)
    DNA_PORTE2 u_dina(.DIN(1'b0),.READ(dna_read),.SHIFT(dna_shift),.CLK(wb_clk_i),.DOUT(dna_data));

    wire [5:0] clk_running;
    wire sel_clockmon = (wb_cyc_i && wb_stb_i && wb_adr_i[6]);
    
    simple_clock_mon #(.NUM_CLOCKS(6))
        u_clkmon( .clk_i(wb_clk_i),
                    .adr_i(wb_adr_i[2 +: 3]),
                    .en_i(sel_clockmon),
                    .wr_i(wb_we_i),
                    .dat_i(wb_dat_i),
                    .dat_o(dat_clockmon),
                    .ack_o(ack_clockmon),
                    .clk_running_o(clk_running),
                    .clk_mon_i( { rackclk_i,
                                  ifclk_i,
                                  clk300_i ,
                                  rxclk_i ,
                                  gtp_clk_i,
                                  aclk_i } ));

    assign aclk_ok_o = clk_running[0];
    assign gtpclk_ok_o = clk_running[1];
    assign rxclk_ok_o = clk_running[2];
    assign rackclk_ok_o = clk_running[5];
    
    assign gpo_o = ctrlstat_gpo;
    assign sync_offset_o = sync_offset;
    
    assign wb_ack_o = (wb_adr_i[6]) ? ack_clockmon : ack_internal;
    assign wb_err_o = 1'b0;
    assign wb_rty_o = 1'b0;
    assign wb_dat_o = (wb_adr_i[6]) ? dat_clockmon : dat_internal;
    
    assign watchdog_null_o = watchdog_null;
    assign watchdog_trigger_o = watchdog_trigger;
    
    assign rfdc_rst_o = rfdc_stream_reset;
    
    assign adc_cal_freeze_o = cal_freeze;
    
endmodule
