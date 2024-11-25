`timescale 1ns / 1ps
// custom adder to compress the fwupd uaddr
// --> probably need to look into hooking this as a secondary
//     adder or something, we'll see.
module fwupd_uaddr(
        input clk_i,
        input ce_i,
        input rstb_i,
        output [7:0] uaddr_o
    );
    // n.b.: firmware loading crap is:
    // each BRAM is 32 kilobits = 4096 bytes = 12 address bits
    // there are 24 of them, split in 2 halves
    // bram_addr_o generates 9 address bits, meaning we need 8 more.
    // we want to make the top bit a bank, so we jump when we get to 12.
    // this is easier than you'd expect because there's a delay.
    // when bit 6:3 = 11 and 2:0 = 7 : 0x5F
    // we want:
    // when bram_addr_o == 9'h1FF:
    //      if fw_update_uaddr_o[6:0] == 0x5F add (4<<3 = 0x20) + 1
    // we can prep for this because there are many many cycles between BRAM jumps
    // so bank_advance <= fw_update_uaddr_o[6:0] == 0x5F;
    // but wait. we're not done - 0x5F is
    // 101_1111
    // meaning that the bank advance is set when [6:5] == 10 and next[5]
    // and we do
    
    // wire [3:0] addr_advance = { bank_advance, 3'b001 };
    // wire [8:0] fw_update_uaddr_next = fw_update_uaddr + addr_advance;
    // but we have to *qualify* bank advance on this because otherwise it breaks the instant
    // it sets:
    // so if (fw_update_uaddr_next[5] && fw_update_uaddr[6:5] == 2'b10) bank_advance <= 1;
    //    else if (fw_update_uaddr[6:5] == 2'b00) bank_advance <= 0;
    // bank_advance <= fw_update_uaddr_next[5] && (fw_update_uaddr[6:5] == 2'b10);
    // so instead of a 7-bit compare, we have a 4-input LUT (bank_advance,
    // fw_update_uaddr_next[5], and fw_update_uaddr[6:5]).
    // pretend it adds every other clock
    // clk  fw_update_uaddr fw_update_uaddr_next bank_advance
    // 0    0x5D            0x5E                 0
    // 1    0x5D            0x5E                 0
    // 2    0x5E            0x5F                 0
    // 3    0x5E            0x5F                 0
    // 4    0x5F            0x60                 0
    // 5    0x5F            0x60                 1
    // 6    0x80            0xA1                 1
    // 7    0x80            0x81                 0
    // sadly, this _will not work_ as a 7-bit adder b/c it'll force
    // the CE/reset uses rather than leaving them open - the tools are
    // not smart enough to allow for this possibility.
    // if we look at the overall requirements, this is actually
    // a bit harder than it seems:
    // assume we factor out the CE in a separate LUT
    // for fw_uaddr we don't have to use the full advance_address, we can
    // just pull out the fw increment.
    // now bit 2:0 needs:
    // fw_uaddr[n], fw_loading[1], and fw_advance_address
    // addend A is 0 for bits [2:1], and bit 0, if !fw_loading or !fw_advance_address and 1 otherwise
    // addend B is 0 if !fw_loading and fw_uaddr[n] otherwise
    // for bit 3, it needs:
    // fw_uaddr[n], fw_loading[1], fw_advance_address, and bank_advance
    // addend A is 1 if fw_loading and fw_advance_address and bank_advance, 0 otherwise
    // addend B is 0 if !fw_loading, fw_uaddr[n] otherwise
    // bits [7:4] have the same logic as bits [2:1]

    // TL;DR:
    // we implement the clock enable/reset adder in pure logic (no control set)
    // bank_advance we'll leave up to synthesis.
    
    // there's no super-dumb way to implement the wr, b/c it's fundamentally dependent on
    // 3 things in 1 clock and we've only got 2 open slots. so we'll leave that up to synth/place.
    // (if we tried to do it as (fw_wr_i && clk_ce_i) || fw_wr_stretch, still takes a LUT2 outside
    // here.
    // but we DO reduce it to just (fw_wr_i || fw_wr_stretch) && clk_ce_i (outside this module)
    // because !fw_loading_i is implied by the reset overriding the CE.
    reg [7:0] uaddr_reg = {8{1'b0}};
    wire [7:0] addend_A;    // O6 output
    wire [7:0] addend_B;    // O5 output
    wire [7:0] carry_out;   // CARRY8 CO
    wire [7:0] sum_out;     // CARRY8 O
    reg bank_advance = 0;
    // bit 0 - 3 input bits, 2 output bits. bit[2:0] are ce, rstb, uaddr_reg[0]
    //          6   5
    // 0 0 0 => 0   0
    // 0 0 1 => 0   0
    // 0 1 0 => 0   0
    // 0 1 1 => 1   0
    // 1 0 0 => 0   0
    // 1 0 1 => 0   0
    // 1 1 0 => 0   1
    // 1 1 1 => 1   1
    // 88888888_C0C0C0C0. bits[2:1] can just be LUT2s
    LUT6_2 #(.INIT(64'h88888888_C0C0C0C0)) u_bit0(.I5(1'b1),.I4(0),.I3(0),
                                                  .I2(ce_i),.I1(rstb_i),.I0(uaddr_reg[0]),
                                                  .O6(addend_A[0]),.O5(addend_B[0]));
    LUT2 #(.INIT(4'hC)) u_bit1(.I1(rstb_i),.I0(uaddr_reg[1]),.O(addend_A[1]));
    assign addend_B[1] = 1'b0;
    LUT2 #(.INIT(4'hC)) u_bit2(.I1(rstb_i),.I0(uaddr_reg[2]),.O(addend_A[2]));
    assign addend_B[2] = 1'b0;
    // bit 3 has an additional input: bank_advance, ce, rst, uaddr_reg[3]
    // O6 is the same (88888888) and if we put bank_advance in I4, the top 16 bits
    // are the same (C0C0) and the bottom are zero.
    LUT6_2 #(.INIT(64'h88888888_C0C00000)) u_bit3(.I5(1'b1),.I4(bank_advance),.I3(1'b0),
                                                  .I2(ce_i),.I1(rstb_i),.I0(uaddr_reg[3]),
                                                  .O6(addend_A[3]),.O5(addend_B[3]));
    // and bits 7:4 are also just LUT2s as before
    LUT2 #(.INIT(4'hC)) u_bit4(.I1(rstb_i),.I0(uaddr_reg[4]),.O(addend_A[4]));
    assign addend_B[4] = 1'b0;
    LUT2 #(.INIT(4'hC)) u_bit5(.I1(rstb_i),.I0(uaddr_reg[5]),.O(addend_A[5]));
    assign addend_B[5] = 1'b0;
    LUT2 #(.INIT(4'hC)) u_bit6(.I1(rstb_i),.I0(uaddr_reg[6]),.O(addend_A[6]));
    assign addend_B[6] = 1'b0;
    LUT2 #(.INIT(4'hC)) u_bit7(.I1(rstb_i),.I0(uaddr_reg[7]),.O(addend_A[7]));
    assign addend_B[8] = 1'b0;
    // ok now the CARRY8
    CARRY8 u_carry8(.DI(addend_B),.S(addend_A),.O(sum_output),.CO(carry_out),.CI(1'b0));
    
    always @(posedge clk_i) begin
        uaddr_reg <= sum_output;
        if (uaddr_reg[6:5] == 2'b10 && carry_out[5])
            bank_advance <= 1;
        else if (uaddr_reg[6:5] == 2'b00)
            bank_advance <= 0;
    end

    assign uaddr_o = uaddr_reg;
endmodule
