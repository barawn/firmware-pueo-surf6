`timescale 1ns / 1ps
`include "interfaces.vh"
// Clock monitors go here.
module surf_id_ctrl(
        input wb_clk_i,
        input wb_rst_i,
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 11, 32),
        
        input [7:0] gpi_i,
        output [7:0] gpo_o,
        output [4:0] sync_offset_o,
        
        // data from TURFIO
        input hsk_rx_i,
        // data to TURFIO
        input hsk_tx_i,
        
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
    
    parameter WB_ADR_BITS = 11;
    
    wire dna_data;
    reg dna_shift = 0;
    reg dna_read = 0;
    (* CUSTOM_CC_SRC = WB_CLK_TYPE *)
    reg [NUM_GPO-1:0] ctrlstat_gpo = {NUM_GPO{1'b0}};
    (* CUSTOM_CC_DST = WB_CLK_TYPE *)
    reg [NUM_GPI-1:0] ctrlstat_gpi = {NUM_GPI{1'b0}};
    
    
    (* CUSTOM_CC_SRC = WB_CLK_TYPE *)
    reg [4:0] sync_offset = {5{1'b0}};
    
    // top 8 bits are a global stat: top bit is TURFIO ready
    wire [31:0] ctrlstat_reg = { rackclk_ok_o, {10{1'b0}}, sync_offset, ctrlstat_gpi, ctrlstat_gpo };
    
    // housekeeping packet count register
    // packet counts are cleared by ANY logical zero on RX, and then
    // increment whenever zeros have been seen for ~18 us or 
    // greater on TX (this will include us, but who cares).
    // as normal we sleaze this by using the overflow.
    localparam [11:0] PACKET_TIMER_RESET_VAL = 12'd248;
    reg [11:0] packet_timer_count = PACKET_TIMER_RESET_VAL;
    reg [3:0] hsk_packet_count = {4{1'b0}};
        
    wire sel_internal = (wb_adr_i[6 +: (WB_ADR_BITS-6)] == 0);
    wire [31:0] wishbone_registers[15:0];
        
    
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

    `WISHBONE_ADDRESS( 12'h000, DEVICE, OUTPUT, [31:0], 0);
    `WISHBONE_ADDRESS( 12'h004, VERSION, OUTPUT, [31:0], 0);
    `WISHBONE_ADDRESS( 12'h008, { {31{1'b0}}, dna_data }, OUTPUTSELECT, sel_dna, 0);
    `WISHBONE_ADDRESS( 12'h00C, ctrlstat_reg, OUTPUTSELECT, sel_ctrlstat, 0);
    `WISHBONE_ADDRESS( 12'h010, hsk_packet_count, OUTPUT, [31:0], 0);
    assign wishbone_registers[4] = wishbone_registers[0];
    assign wishbone_registers[5] = wishbone_registers[1];
    assign wishbone_registers[6] = wishbone_registers[2];
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
    always @(posedge wb_clk_i) begin
        if (hsk_tx_i) packet_timer_count <= PACKET_TIMER_RESET_VAL;
        else packet_timer_count <= packet_timer_count[10:0] + 1;

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
    
endmodule
