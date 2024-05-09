`timescale 1ns / 1ps
// This is based on the rxclk_sysclk_transfer module, but in the SURF
// this is slightly harder because we need to equalize the clock rates.

// So what we do is first
// 1: transfer data_i from rxclk_i to rxclk_x3_i (data_x3_i) domain using rxclk_ce 
// 2: transfer data_x3_i and rxclk_ce to aclk
// 3: build up the full 32 bit message every 8 transfers (24 aclk periods)
//
// The transfer from rxclk_x3 -> aclk is done the same way as rxclk-to-sysclk
// 1. create a toggle flop in aclk
// 2. capture in rxclk_x3_i
// 3. recapture in aclk
// 4. xor the toggle flop and the recapture
//
// and then phase shift rxclk until we get a clean transfer.
// We lock data_x3_i, rxclk_ce, and the 2 toggle flops in a slice.

// This is the mod
// This is the module that transfers from RXCLK over to SYSCLK.
// It also includes a capture-tracking mechanism.
// Basically, what we need to do is guarantee that we go from
// RXCLK to SYSCLK in exactly one clock cycle - so the way
// we do that is
// 1) create a toggle flop in SYSCLK
// 2) capture in RXCLK
// 3) recapture in SYSCLK
// 4) XOR the toggle flop and the recapture, which should be identical.
//
// Because setup/hold times on FPGA FFs are negligible (more typically
// around 200 ps, regardless of what the datasheet says) this imposes
// an alignment between the two clocks roughly equal to or better than the
// data path delay between the two. That is, the data change has to be *in flight*
// between the launch FF and the target FF, otherwise you won't end up
// with the correct propagation delay.
//
// The flops in the RXCLK and SYSCLK domain are all constrained to be in
// the same slice here, and we change the minimum datapath delay to
// 2 ns, leaving the setup constraint the same.
module rxclk_aclk_transfer(
        input rxclk_i,
        input rxclk_x3_i,
        input rxclk_ce_i,
        input [3:0] data_i,
        input aclk_i,
        output [3:0] data_o,
        output data_ce_o,
        output capture_err_o
    );

    // with phase tracking, this means:
    // rxclk_ce_i occurs on clock 0 out of 2
    // rxclk_x3_ce_reg occurs on clock 1 out of 2
    // rxclk_x3_ce occurs on clock 2 out of 2
    // data_ce_o is back on clock 0 out of 2 (neat)

    // we reregister the data to allow the aligned guys to have more placement
    // constraint.
    reg [3:0]   rxclk_x3_data_reg = {4{1'b0}};
    reg         rxclk_x3_ce_reg = 1'b0;

    // internal aclk-side wires
    wire        aclk_toggle;
    wire        aclk_recapt;
    // internal rxclk_x3-side wires
    wire        rxclk_x3_capture;
    wire [3:0]  rxclk_x3_data;
    wire        rxclk_x3_ce;        
    
    (* RLOC = "X0Y0", HU_SET = "aclkcap0", CUSTOM_RXCLK_ACLK_SOURCE = "TRUE" *)
    FD u_aclk_tog(.C(aclk_i),.D(~aclk_toggle),.Q(aclk_toggle));
    (* RLOC = "X0Y0", HU_SET = "aclkcap0", CUSTOM_RXCLK_ACLK_TARGET = "TRUE" *)
    FD u_aclk_rcp(.C(aclk_i),.D(rxclk_x3_capture),.Q(aclk_recapt));
    (* RLOC = "X0Y0", HU_SET = "aclkcap0", CUSTOM_RXCLK_ACLK_TARGET = "TRUE" *)
    FD u_aclk_d0(.C(aclk_i),.D(rxclk_x3_data[0]),.Q(data_o[0]));
    (* RLOC = "X0Y0", HU_SET = "aclkcap0", CUSTOM_RXCLK_ACLK_TARGET = "TRUE" *)
    FD u_aclk_d1(.C(aclk_i),.D(rxclk_x3_data[1]),.Q(data_o[1]));
    (* RLOC = "X0Y0", HU_SET = "aclkcap0", CUSTOM_RXCLK_ACLK_TARGET = "TRUE" *)
    FD u_aclk_d2(.C(aclk_i),.D(rxclk_x3_data[2]),.Q(data_o[2]));
    (* RLOC = "X0Y0", HU_SET = "aclkcap0", CUSTOM_RXCLK_ACLK_TARGET = "TRUE" *)
    FD u_aclk_d3(.C(aclk_i),.D(rxclk_x3_data[3]),.Q(data_o[3]));
    (* RLOC = "X0Y0", HU_SET = "aclkcap0", CUSTOM_RXCLK_ACLK_TARGET = "TRUE" *)
    FD u_aclk_ce(.C(aclk_i),.D(rxclk_x3_ce),.Q(data_ce_o));
    
    // rxclk_x3 side
    (* RLOC = "X0Y0", HU_SET = "rxcap0", CUSTOM_RXCLK_ACLK_SOURCE = "TRUE", CUSTOM_RXCLK_ACLK_TARGET = "TRUE" *)
    FD u_rxc_cap(.C(rxclk_x3_i),.D(aclk_toggle),.Q(rxclk_x3_capture));
    (* RLOC = "X0Y0", HU_SET = "rxcap0", CUSTOM_RXCLK_ACLK_SOURCE = "TRUE" *)
    FD u_rxc_cd0(.C(rxclk_x3_i),.D(rxclk_x3_data_reg[0]),.Q(rxclk_x3_data[0]));
    (* RLOC = "X0Y0", HU_SET = "rxcap0", CUSTOM_RXCLK_ACLK_SOURCE = "TRUE" *)
    FD u_rxc_cd1(.C(rxclk_x3_i),.D(rxclk_x3_data_reg[1]),.Q(rxclk_x3_data[1]));
    (* RLOC = "X0Y0", HU_SET = "rxcap0", CUSTOM_RXCLK_ACLK_SOURCE = "TRUE" *)
    FD u_rxc_cd2(.C(rxclk_x3_i),.D(rxclk_x3_data_reg[2]),.Q(rxclk_x3_data[2]));
    (* RLOC = "X0Y0", HU_SET = "rxcap0", CUSTOM_RXCLK_ACLK_SOURCE = "TRUE" *)
    FD u_rxc_cd3(.C(rxclk_x3_i),.D(rxclk_x3_data_reg[3]),.Q(rxclk_x3_data[3]));
    (* RLOC = "X0Y0", HU_SET = "rxcap0", CUSTOM_RXCLK_ACLK_SOURCE = "TRUE" *)
    FD u_rxc_ce(.C(rxclk_x3_i),.D(rxclk_x3_ce_reg),.Q(rxclk_x3_ce));

    always @(posedge rxclk_x3_i) begin
        if (rxclk_ce_i) rxclk_x3_data_reg <= data_i;
        rxclk_x3_ce_reg <= rxclk_ce_i;
    end        

    reg aclk_rxclk_x3_biterr = 0;
    always @(posedge aclk_i) begin
        aclk_rxclk_x3_biterr <= aclk_toggle ^ aclk_recapt;
    end
    assign capture_err_o = aclk_rxclk_x3_biterr;
endmodule
