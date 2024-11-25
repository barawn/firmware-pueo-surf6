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
    // the firmware loading crap is a custom adder
    // because we want to count up to uaddr[7:3] == 11, then jump
    // to uaddr[7:3] = 16.
    // we do this by detecting the carry output going and
    // turning that into a single add to jump up to 16.
    // for the full uaddr, it's 95 -> 128
    //
    // bank_advance needs to act like ce as well in order to
    // force the jump, but this only happens at bit 5.
    // this means we actually do 95->96->128, but that's
    // fine because ce_i can't happen in two consecutive
    // cycles.
    reg [7:0] uaddr_reg = {8{1'b0}};
    wire [7:0] halfadder;    // O6 output
    wire [7:0] addend_B;    // O5 output
    wire [7:0] carry_out;   // CARRY8 CO
    wire [7:0] sum_out;     // CARRY8 O
    reg bank_advance = 0;
    // bit 0 - 3 input bits, 2 output bits. bit[3:0] are ce, rstb, uaddr_reg[0]
    // the O6 output is halfadder (addend_A ^ addend_B) and O5 is addend_B
    //          6   5   addend_A    addend_B
    // 0 0 0 => 0   0   0           0
    // 0 0 1 => 0   0   0           0
    // 0 1 0 => 0   0   0           0
    // 0 1 1 => 0   0   0           0
    // 1 0 0 => 0   0   0           0
    // 1 0 1 => 1   0   1           0
    // 1 1 0 => 1   1   0           1
    // 1 1 1 => 0   1   1           1
    // 60606060_C0C0C0C0. bits[2:1] can just be LUT2s
    LUT6_2 #(.INIT(64'h60606060_C0C0C0C0)) u_bit0(.I5(1'b1),.I4(0),.I3(0),
                                                  .I2(rstb_i),.I1(ce_i),.I0(uaddr_reg[0]),
                                                  .O6(halfadder[0]),.O5(addend_B[0]));
    // rstb uaddr_reg   halfadder
    // 0    0           0
    // 0    1           0
    // 1    0           0
    // 1    1           1                                 
    LUT2 #(.INIT(4'h8)) u_bit1(.I1(rstb_i),.I0(uaddr_reg[1]),.O(halfadder[1]));
    assign addend_B[1] = 1'b0;
    LUT2 #(.INIT(4'h8)) u_bit2(.I1(rstb_i),.I0(uaddr_reg[2]),.O(halfadder[2]));
    assign addend_B[2] = 1'b0;
    LUT2 #(.INIT(4'h8)) u_bit3(.I1(rstb_i),.I0(uaddr_reg[3]),.O(halfadder[3]));
    assign addend_B[3] = 1'b0;
    LUT2 #(.INIT(4'h8)) u_bit4(.I1(rstb_i),.I0(uaddr_reg[4]),.O(halfadder[4]));
    assign addend_B[4] = 1'b0;
    // bit 5 has an additional input: rst, ce, ba, ur
    // the entire first 8 are 0 due to reset
    // rs ce ba ur  O6  O5  addend_A addend_B
    //  1  0  0  0  0   0   0        0
    //  1  0  0  1  1   0   1        0
    //  1  0  1  0  1   0   0        1
    //  1  0  1  1  0   1   1        1
    //  1  1  0  0  0   0   0        0
    //  1  1  0  1  1   0   1        0
    //  1  1  1  0  0   0   0        0 <-- can't happen
    //  1  1  1  1  1   0   1        0 <-- can't happen
    //  O6 = A6, O5 = 08
    LUT6_2 #(.INIT(64'hA600A600_08000800)) u_bit5(.I5(1'b1),.I4(1'b0),.I3(rstb_i),
                                                  .I2(ce_i),.I1(bank_advance),.I0(uaddr_reg[5]),
                                                  .O6(halfadder[5]),.O5(addend_B[5]));
    // and bits 7:6 are also just LUT2s as before
    LUT2 #(.INIT(4'h8)) u_bit6(.I1(rstb_i),.I0(uaddr_reg[6]),.O(halfadder[6]));
    assign addend_B[6] = 1'b0;
    LUT2 #(.INIT(4'h8)) u_bit7(.I1(rstb_i),.I0(uaddr_reg[7]),.O(halfadder[7]));
    assign addend_B[7] = 1'b0;
    // ok now the CARRY8
    CARRY8 u_carry8(.DI(addend_B),.S(halfadder),.O(sum_out),.CO(carry_out),.CI(1'b0));
    
    always @(posedge clk_i) begin
        uaddr_reg <= sum_out;
        // the CO's are shifted up a bit: carry_out[4] indicates
        // uaddr_reg[4:0] are all 1: this means uaddr = 101_1111 = 95. we then add 33
        // and jump to 128.
        bank_advance <= (uaddr_reg[6:5] == 2'b10) && carry_out[4];
    end

    assign uaddr_o = uaddr_reg;
endmodule
