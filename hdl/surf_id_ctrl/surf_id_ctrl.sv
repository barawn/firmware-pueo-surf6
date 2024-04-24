`timescale 1ns / 1ps
`include "interfaces.vh"
// Clock monitors go here.
module surf_id_ctrl(
        input wb_clk_i,
        input wb_rst_i,
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 11, 32),
        
                
        input if_clk_i,     // 125 MHz
        input sys_clk_i,    // 375 MHz
        input gtp_clk_i,    // GTP clock
        input rx_clk_i,     // receive clock from TURF
        input clk300_i      // 300 MHz used for IDELAYCTRL
    );
    
    parameter [31:0] DEVICE = "SURF";
    parameter [31:0] VERSION = {32{1'b0}};
    parameter WB_CLK_TYPE = "PSCLK";
    
    wire dna_data;
    reg dna_shift = 0;
    reg dna_read = 0;
    
    wire [31:0] ctrlstat_reg;
    assign ctrlstat_reg = {32{1'b0}};
    
    wire sel_internal = (wb_adr_i[6 +: 6] == 0);
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
    
    always @(posedge wb_clk_i) begin
        ack_internal <= (wb_cyc_i && wb_stb_i && sel_internal) && !ack_internal;
        if (sel_dna && ~wb_we_i && wb_ack_o) dna_shift <= 1;
        else dna_shift <= 0;
        if (sel_dna && wb_we_i && wb_ack_o && wb_sel_i[3]) dna_read <= wb_dat_i[31];
        else dna_read <= 0;        
    end    
    DNA_PORTE2 u_dina(.DIN(1'b0),.READ(dna_read),.SHIFT(dna_shift),.CLK(wb_clk_i),.DOUT(dna_data));

    wire [3:0] clk_running;
    wire sel_clockmon = (wb_cyc_i && wb_stb_i && wb_adr_i[6]);
    
    simple_clock_mon #(.NUM_CLOCKS(4))
        u_clkmon( .clk_i(wb_clk_i),
                    .adr_i(wb_adr_i[2 +: 3]),
                    .en_i(sel_clockmon),
                    .wr_i(wb_we_i),
                    .dat_i(wb_dat_i),
                    .dat_o(dat_clockmon),
                    .ack_o(ack_clockmon),
                    .clk_running_o(clk_running),
                    .clk_mon_i( { clk300_i ,
                                  rx_clk_i ,
                                  gtp_clk_i,
                                  sys_clk_i } ));

    assign wb_ack_o = (wb_adr_i[6]) ? ack_clockmon : ack_internal;
    assign wb_err_o = 1'b0;
    assign wb_rty_o = 1'b0;
    assign wb_dat_o = (wb_adr_i[6]) ? dat_clockmon : dat_internal;
    
endmodule
